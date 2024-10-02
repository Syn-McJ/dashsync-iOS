//
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DSMasternodeGroup.h"
#import "DSChainManager.h"
#import "DSChain+Protected.h"
#import "DSCoinJoinManager.h"
#import "DSSimplifiedMasternodeEntry.h"
#import "DSMasternodeManager.h"
#import "DSPeerManager.h"
#import "DSSendCoinJoinQueue.h"
#import "DSBackoff.h"
#import "DSBlock.h"
#import "DSPeerManager+Protected.h"
#import <arpa/inet.h>

float_t const MIN_PEER_DISCOVERY_INTERVAL = 1; // One second
float_t const DEFAULT_INITIAL_BACKOFF = 1; // One second
float_t const DEFAULT_MAX_BACKOFF = 5; // Five seconds
float_t const GROUP_BACKOFF_MULTIPLIER = 1.5;
float_t const BACKOFF_MULTIPLIER = 1.001;

@interface DSMasternodeGroup ()

@property (nonatomic, strong) DSChain *chain;
@property (nonatomic, weak, nullable) DSCoinJoinManager *coinJoinManager;
@property (nonatomic, strong) NSMutableSet<NSValue *> *pendingSessions;
@property (nonatomic, strong) NSMutableDictionary *masternodeMap;
@property (nonatomic, strong) NSMutableDictionary *sessionMap;
@property (nonatomic, strong) NSMutableDictionary *addressMap;
@property (atomic, readonly) NSUInteger maxConnections;
@property (nonatomic, strong) NSMutableArray<DSPeer *> *mutablePendingClosingMasternodes;
@property (nonatomic, strong) NSMutableSet *mutableConnectedPeers;
@property (nonatomic, strong) NSMutableSet *mutablePendingPeers;
@property (nonatomic, strong) NSObject *peersLock;
@property (nonatomic, readonly) BOOL shouldSendDsq;
@property (nullable, nonatomic, readwrite) DSPeer *downloadPeer;
@property (nonatomic, strong) DSBackoff *groupBackoff;
@property (nonatomic, strong) NSMutableDictionary<NSString*, DSBackoff*> *backoffMap;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic) uint32_t lastSeenBlock;

@end

@implementation DSMasternodeGroup

- (instancetype)initWithManager:(DSCoinJoinManager *)manager {
    self = [super init];
    if (self) {
        _coinJoinManager = manager;
        _chain = manager.chain;
        _pendingSessions = [NSMutableSet set];
        _mutablePendingClosingMasternodes = [NSMutableArray array];
        _masternodeMap = [NSMutableDictionary dictionary];
        _sessionMap = [NSMutableDictionary dictionary];
        _addressMap = [NSMutableDictionary dictionary];
        _mutableConnectedPeers = [NSMutableSet set];
        _mutablePendingPeers = [NSMutableSet set];
        _downloadPeer = nil;
        _maxConnections = 0;
        _shouldSendDsq = true;
        _groupBackoff = [[DSBackoff alloc] initInitialBackoff:DEFAULT_INITIAL_BACKOFF maxBackoff:DEFAULT_MAX_BACKOFF multiplier:GROUP_BACKOFF_MULTIPLIER];
        _backoffMap = [NSMutableDictionary dictionary];
        _lastSeenBlock = 0;
    }
    return self;
}

- (void)startAsync {
    _isRunning = true;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSyncStateDidChangeNotification:)
                                                 name:DSChainManagerSyncStateDidChangeNotification
                                               object:nil];
    [self triggerConnections];
}

- (dispatch_queue_t)networkingQueue {
    return self.chain.networkingQueue;
}

- (void)stopAsync {
    _isRunning = false;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isMasternodeOrDisconnectRequested:(UInt128)ip port:(uint16_t)port {
    BOOL found = [self forPeer:ip port:port warn:NO withPredicate:^BOOL(DSPeer *peer) {
        return YES;
    }];
    
    if (!found) {
        for (DSPeer *mn in self.pendingClosingMasternodes) {
            if (uint128_eq(mn.address, ip) && mn.port == port) {
                found = true;
            }
        }
    }
    
    return found;
}

- (BOOL)disconnectMasternode:(UInt128)ip port:(uint16_t)port {
    return [self forPeer:ip port:port warn:YES withPredicate:^BOOL(DSPeer *peer) {
        DSLog(@"[OBJ-C] CoinJoin: masternode[closing] %@", [self hostFor:ip]);
        
        @synchronized (self.mutablePendingClosingMasternodes) {
            [self.mutablePendingClosingMasternodes addObject:peer];
            // TODO (dashj): what if this disconnects the wrong one
            [self updateMaxConnections];
        }
        
        [peer disconnect];
        
        return true;
    }];
}

- (BOOL)forPeer:(UInt128)ip port:(uint16_t)port warn:(BOOL)warn withPredicate:(BOOL (^)(DSPeer *peer))predicate {
    NSMutableString *listOfPeers = [NSMutableString string];
    NSSet *peers = self.connectedPeers;
    
    for (DSPeer *peer in peers) {
        [listOfPeers appendFormat:@"%@, ", peer.location];
        
        if (uint128_eq(peer.address, ip) && peer.port == port) {
            return predicate(peer);
        }
    }
    
    if (warn) {
        if (![self isNodePending:ip port:port]) {
            DSLog(@"[OBJ-C] CoinJoin: Cannot find %@ in the list of connected peers: %@", [self hostFor:ip], listOfPeers);
            NSAssert(NO, @"Cannot find %@", [self hostFor:ip]);
        } else {
            DSLog(@"[OBJ-C] CoinJoin: %@ in the list of pending peers", [self hostFor:ip]);
        }
    }
    
    return NO;
}

- (BOOL)isNodePending:(UInt128)ip port:(uint16_t)port {
    for (DSPeer *peer in self.pendingPeers) {
        if (uint128_eq(peer.address, ip) && peer.port == port) {
            return true;
        }
    }
    
    return false;
}

- (NSSet *)connectedPeers {
    @synchronized(self.peersLock) {
        return [self.mutableConnectedPeers copy];
    }
}

- (NSSet *)pendingPeers {
    @synchronized(self.peersLock) {
        return [self.mutablePendingPeers copy];
    }
}

- (NSMutableArray *)pendingClosingMasternodes {
    @synchronized(self.mutablePendingClosingMasternodes) {
        return [self.mutablePendingClosingMasternodes copy];
    }
}

- (void)triggerConnections {
    [self triggerConnectionsJobWithDelay:0];
}

- (void)triggerConnectionsJobWithDelay:(NSTimeInterval)delay {
    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
    dispatch_after(delayTime, self.networkingQueue, ^{
        if (!self.isRunning) {
            return;
        }
        
        if (!self.coinJoinManager.isChainSynced || self.coinJoinManager.isWaitingForNewBlock || !self.coinJoinManager.isMixing) {
            return;
        }
        
        @synchronized (self.groupBackoff) {
            NSUInteger numPeers = self.mutablePendingPeers.count + self.mutableConnectedPeers.count;

            if (numPeers >= self.maxConnections) {
                return;
            }

            NSDate *now = [NSDate date];
            DSPeer *peerToTry = [self getNextPendingMasternode];

            if (peerToTry) {
                NSDate *retryTime = [self.backoffMap objectForKey:peerToTry.location].retryTime;
                retryTime = [retryTime laterDate:self.groupBackoff.retryTime];
                NSTimeInterval delay = [retryTime timeIntervalSinceDate:now];
            
                if (delay > 0.1) {
                    DSLog(@"[OBJ-C] CoinJoin: Waiting %fl s before next connect attempt to masternode to %@", delay, peerToTry == NULL ? @"" : peerToTry.location);
                    [self triggerConnectionsJobWithDelay:delay];
                    return;
                }
                
                [self connectTo:peerToTry];
                [self.groupBackoff trackSuccess];
            } else {
                [self.groupBackoff trackFailure];
            }
        }
        
        NSUInteger count = self.mutablePendingPeers.count + self.mutableConnectedPeers.count;
        
        if (count < self.maxConnections) {
            [self triggerConnectionsJobWithDelay:0]; // Try next peer immediately.
        }
    });
}

- (DSPeer *)getNextPendingMasternode {
    @synchronized(self.addressMap) {
        NSArray *pendingSessionsCopy = [self.pendingSessions copy];
        DSPeer *peerWithLeastBackoff = nil;
        NSValue *sessionValueWithLeastBackoff = nil;
        UInt256 sessionId = UINT256_ZERO;
        NSDate *leastBackoffTime = [NSDate distantFuture];
        
        for (NSValue *sessionValue in pendingSessionsCopy) {
            [sessionValue getValue:&sessionId];
            DSSimplifiedMasternodeEntry *mixingMasternodeInfo = [self mixingMasternodeAddressFor:sessionId];
            
            if (mixingMasternodeInfo) {
                UInt128 ipAddress = mixingMasternodeInfo.address;
                uint16_t port = mixingMasternodeInfo.port;
                DSPeer *peer = [self peerForLocation:ipAddress port:port];
                
                if (peer == nil) {
                    peer = [DSPeer peerWithAddress:ipAddress andPort:port onChain:self.chain];
                }
                
                if (![self.mutablePendingClosingMasternodes containsObject:peer] && ![self isNodeConnected:peer] && ![self isNodePending:peer]) {
                    DSBackoff *backoff = [self.backoffMap objectForKey:peer.location];
                    
                    if (!backoff) {
                        backoff = [[DSBackoff alloc] initInitialBackoff:DEFAULT_INITIAL_BACKOFF maxBackoff:DEFAULT_MAX_BACKOFF multiplier:BACKOFF_MULTIPLIER];
                        [self.backoffMap setObject:backoff forKey:peer.location];
                    }
                    
                    if ([backoff.retryTime compare:leastBackoffTime] == NSOrderedAscending) {
                        leastBackoffTime = backoff.retryTime;
                        peerWithLeastBackoff = peer;
                        sessionValueWithLeastBackoff = sessionValue;
                    }
                }
            }
        }
        
        if (peerWithLeastBackoff) {
            [self.addressMap setObject:sessionValueWithLeastBackoff forKey:peerWithLeastBackoff.location];
            DSLog(@"[OBJ-C] CoinJoin: discovery: %@ -> %@", peerWithLeastBackoff.location, uint256_hex(sessionId));
        }

        return peerWithLeastBackoff;
    }
}

- (DSSimplifiedMasternodeEntry *)mixingMasternodeAddressFor:(UInt256)sessionId {
    NSValue *sessionIdKey = [NSValue value:&sessionId withObjCType:@encode(UInt256)];
    NSValue *proTxHashValue = [self.sessionMap objectForKey:sessionIdKey];
    
    if (proTxHashValue) {
        UInt256 proTxHash = UINT256_ZERO;
        [proTxHashValue getValue:&proTxHash];
        
        return [self.coinJoinManager masternodeEntryByHash:proTxHash];
    }
    
    return nil;
}

- (BOOL)addPendingMasternode:(UInt256)proTxHash clientSessionId:(UInt256)sessionId {
    @synchronized (self.pendingSessions) {
        DSLog(@"[OBJ-C] CoinJoin: adding masternode for mixing. maxConnections = %lu, protx: %@, sessionId: %@", (unsigned long)_maxConnections, uint256_hex(proTxHash), uint256_hex(sessionId));
        NSValue *sessionIdValue = [NSValue valueWithBytes:&sessionId objCType:@encode(UInt256)];
        [self.pendingSessions addObject:sessionIdValue];
        
        NSValue *proTxHashKey = [NSValue value:&proTxHash withObjCType:@encode(UInt256)];
        [self.masternodeMap setObject:sessionIdValue forKey:proTxHashKey];
        [self.sessionMap setObject:proTxHashKey forKey:sessionIdValue];
        
        [self checkMasternodesWithoutSessions];
        [self updateMaxConnections];
    }
    
    return true;
}

- (void)updateMaxConnections {
    _maxConnections = self.pendingSessions.count;
    NSUInteger connections = MIN(self.maxConnections, self.coinJoinManager.options->coinjoin_sessions);
    DSLog(@"[OBJ-C] CoinJoin: updating max connections to min(%lu, %lu)", (unsigned long)_maxConnections, (unsigned long)self.coinJoinManager.options->coinjoin_sessions);
    
    [self updateMaxConnections:connections];
}

- (void)updateMaxConnections:(NSUInteger)connections {
    _maxConnections = connections;
    
    if (!self.isRunning) {
        return;
    }
    
    // We may now have too many or too few open connections. Add more or drop some to get to the right amount.
    NSInteger adjustment = 0;
    
    @synchronized (self.peersLock) {
        NSUInteger pendingCount = self.mutablePendingPeers.count;
        NSUInteger connectedCount = self.mutableConnectedPeers.count;
        NSUInteger numPeers = pendingCount + connectedCount;
        adjustment = self.maxConnections - numPeers;
        DSLog(@"[OBJ-C] CoinJoin: updateMaxConnections adjustment %lu, pendingCount: %lu, connectedCount: %lu", adjustment, pendingCount, connectedCount);
    }
    
    if (adjustment > 0) {
        [self triggerConnections];
    }
}

- (void)checkMasternodesWithoutSessions {
    NSMutableArray *masternodesToDrop = [NSMutableArray array];
    
    for (DSPeer *peer in self.connectedPeers) {
        BOOL found = false;
            
        for (NSValue *value in self.pendingSessions) {
            UInt256 sessionId;
            [value getValue:&sessionId];
            DSSimplifiedMasternodeEntry *mixingMasternodeAddress = [self mixingMasternodeAddressFor:sessionId];
                
            if (mixingMasternodeAddress) {
                UInt128 ipAddress = mixingMasternodeAddress.address;
                uint16_t port = mixingMasternodeAddress.port;
                    
                if (uint128_eq(ipAddress, peer.address) && port == peer.port) {
                    found = YES;
                }
            } else {
                // TODO(DashJ): we may not need this anymore
                DSLog(@"[OBJ-C] CoinJoin: session is not connected to a masternode: %@", uint256_hex(sessionId));
            }
        }
        
        if (!found) {
            DSLog(@"[OBJ-C] CoinJoin: masternode is not connected to a session: %@", peer.location);
            [masternodesToDrop addObject:peer];
        }
    }
    
    DSLog(@"[OBJ-C] CoinJoin: need to drop %lu masternodes", (unsigned long)masternodesToDrop.count);
    
    for (DSPeer *peer in masternodesToDrop) {
        DSSimplifiedMasternodeEntry *mn = [_chain.chainManager.masternodeManager masternodeAtLocation:peer.address port:peer.port];
        DSLog(@"[OBJ-C] CoinJoin: masternode will be disconnected: %@: %@", peer.location, uint256_hex(mn.providerRegistrationTransactionHash));
        [self.mutablePendingClosingMasternodes addObject:peer];
        [peer disconnect];
    }
}

- (NSString *)hostFor:(UInt128)address {
    char s[INET6_ADDRSTRLEN];

    if (address.u64[0] == 0 && address.u32[2] == CFSwapInt32HostToBig(0xffff)) {
        return @(inet_ntop(AF_INET, &address.u32[3], s, sizeof(s)));
    } else
        return @(inet_ntop(AF_INET6, &address, s, sizeof(s)));
}

- (BOOL)connectTo:(DSPeer *)peer {
    DSLog(@"[OBJ-C] CoinJoin: connectTo: %@", peer.location);
    
    if (![self isMasternodeSessionByPeer:peer]) {
        DSLog(@"[OBJ-C] CoinJoin: %@ not a masternode session, exit", peer.location);
        return NO;
    }
    
    if ([self isNodeConnected:peer] || [self isNodePending:peer]) {
        DSLog(@"[OBJ-C] CoinJoin: attempting to connect to the same masternode again: %@", peer.location);
        return NO; // do not connect to the same peer again
    }
    
    DSSimplifiedMasternodeEntry *mn = [_chain.chainManager.masternodeManager masternodeAtLocation:peer.address port:peer.port];
    UInt256 sessionId = UINT256_ZERO;
    
    @synchronized (self.masternodeMap) {
        UInt256 proTxHash = mn.providerRegistrationTransactionHash;
        NSValue *proTxHashKey = [NSValue value:&proTxHash withObjCType:@encode(UInt256)];
        NSValue *sessionObject = [self.masternodeMap objectForKey:proTxHashKey];
        
        if (sessionObject) {
            [sessionObject getValue:&sessionId];
        }
    }
    
    if (uint256_is_zero(sessionId)) {
        DSLog(@"[OBJ-C] CoinJoin: session is not connected to a masternode, proTxHashKey not found in masternodeMap");
        return NO;
    }
    
    DSSimplifiedMasternodeEntry *mixingMasternodeAddress = [self mixingMasternodeAddressFor:sessionId];
    
    if (!mixingMasternodeAddress) {
        DSLog(@"[OBJ-C] CoinJoin: session is not connected to a masternode, sessionId: %@", uint256_hex(sessionId));
        return NO;
    }
    
    DSLog(@"[OBJ-C] CoinJoin: masternode[connecting] %@: %@; %@", peer.location, uint256_hex(mn.providerRegistrationTransactionHash), uint256_hex(sessionId));
    
    [peer setChainDelegate:self.chain.chainManager peerDelegate:self transactionDelegate:self.chain.chainManager.transactionManager governanceDelegate:self.chain.chainManager.governanceSyncManager sporkDelegate:self.chain.chainManager.sporkManager masternodeDelegate:self.chain.chainManager.masternodeManager queue:self.networkingQueue];
    peer.earliestKeyTime = self.chain.earliestWalletCreationTime;;

    @synchronized (self.peersLock) {
        [self.mutablePendingPeers addObject:peer];
    }
    
    [peer connect];
    
    return YES;
}

- (BOOL)isMasternodeSessionByPeer:(DSPeer *)peer {
    @synchronized (self.addressMap) {
        return [self.addressMap objectForKey:peer.location] != nil;
    }
}

- (BOOL)isNodeConnected:(DSPeer *)node {
    return [self forPeer:node.address port:node.port warn:NO withPredicate:^BOOL(DSPeer * _Nonnull peer) {
        return YES;
    }];
}

- (BOOL)isNodePending:(DSPeer *)node {
    for (DSPeer *peer in self.pendingPeers) {
        if (uint128_eq(node.address, peer.address) && node.port == peer.port) {
            return YES;
        }
    }
    
    return NO;
}

- (void)peerConnected:(nonnull DSPeer *)peer {
    @synchronized (self.peersLock) {
        [self.groupBackoff trackSuccess];
        [[self.backoffMap objectForKey:peer.location] trackSuccess];
        
        DSLog(@"[OBJ-C] CoinJoin: New peer %@ ({%lu connected, %lu pending, %lu max)", peer.location, self.mutableConnectedPeers.count, self.mutablePendingPeers.count, self.maxConnections);
        
        [self.mutablePendingPeers removeObject:peer];
        [self.mutableConnectedPeers addObject:peer];
    }
    
    if (self.shouldSendDsq) {
        [peer sendRequest:[DSSendCoinJoinQueue requestWithShouldSend:true]];
    }
}

- (void)peer:(nonnull DSPeer *)peer disconnectedWithError:(nonnull NSError *)error {
    @synchronized (self.peersLock) {
        [self.mutablePendingPeers removeObject:peer];
        [self.mutableConnectedPeers removeObject:peer];
        
        DSLog(@"[OBJ-C] CoinJoin: %@ died with error %@: (%lu connected, %lu pending, %lu max)", peer.location, error, (unsigned long)self.mutableConnectedPeers.count, (unsigned long)self.mutablePendingPeers.count, (unsigned long)self.maxConnections);
        
        [self.groupBackoff trackFailure];
        [[self.backoffMap objectForKey:peer.location] trackFailure];
        NSUInteger numPeers = self.mutablePendingPeers.count + self.mutableConnectedPeers.count;

        if (numPeers < self.maxConnections) {
            [self triggerConnections];
        }
    }
     
    @synchronized (self.pendingSessions) {
        DSPeer *masternode = NULL;
        
        for (DSPeer *mn in self.pendingClosingMasternodes) {
            if ([peer.location isEqualToString:mn.location]) {
                masternode = mn;
            }
        }
        
        DSLog(@"[OBJ-C] CoinJoin: handling this mn peer death: %@ -> %@", peer.location, masternode != NULL ? masternode.location : @"not found in closing list");
        
        if (masternode) {
            NSString *address = peer.location;
            
            if ([self.mutablePendingClosingMasternodes containsObject:masternode]) {
                // if this is part of pendingClosingMasternodes, where we want to close the connection,
                // we don't want to increase the backoff time
                [[self.backoffMap objectForKey:address] trackSuccess];
            }
            
            [self.mutablePendingClosingMasternodes removeObject:masternode];
            UInt256 proTxHash = [self.chain.chainManager.masternodeManager masternodeAtLocation:masternode.address port:masternode.port].providerRegistrationTransactionHash;
            NSValue *proTxHashKey = [NSValue valueWithBytes:&proTxHash objCType:@encode(UInt256)];
            NSValue *sessionIdObject = [self.masternodeMap objectForKey:proTxHashKey];
            
            if (sessionIdObject) {
                [self.pendingSessions removeObject:sessionIdObject];
                [self.sessionMap removeObjectForKey:sessionIdObject];
            }
            
            [self.masternodeMap removeObjectForKey:proTxHashKey];
            [self.addressMap removeObjectForKey:masternode.location];
        }
        
        [self checkMasternodesWithoutSessions];
    }
}

- (void)peer:(nonnull DSPeer *)peer relayedPeers:(nonnull NSArray *)peers {
    // TODO ?
}

- (DSPeer *)peerForLocation:(UInt128)ipAddress port:(uint16_t)port {
    for (DSPeer *peer in self.connectedPeers) {
        if (uint128_eq(peer.address, ipAddress) && peer.port == port) {
            return peer;
        }
    }
    
    for (DSPeer *peer in self.pendingPeers) {
        if (uint128_eq(peer.address, ipAddress) && peer.port == port) {
            return peer;
        }
    }
    
    return [self.chain.chainManager.peerManager peerForLocation:ipAddress port:port];
}

- (void)handleSyncStateDidChangeNotification:(NSNotification *)note {
    if ([note.userInfo[DSChainManagerNotificationChainKey] isEqual:[self chain]] && self.chain.lastSyncBlock.height > self.lastSeenBlock) {
        self.lastSeenBlock = self.chain.lastSyncBlock.height;
        DSLog(@"[OBJ-C] CoinJoin: new block found, restarting masternode connections job");
        [self triggerConnections];
    }
}

@end
