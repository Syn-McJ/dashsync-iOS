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

#import <Foundation/Foundation.h>
#import "DSChain.h"
#import "DSTransactionOutput.h"
#import "DSCoinControl.h"
#import "DSCompactTallyItem.h"
#import "DSCoinJoinManager.h"
#import "DSCoinJoinWrapper.h"
#import "DSMasternodeGroup.h"

NS_ASSUME_NONNULL_BEGIN

@interface DSCoinJoinManager : NSObject

@property (nonatomic, assign, nullable) DSChainManager *chainManager;
@property (nonatomic, strong, nullable) DSMasternodeGroup *masternodeGroup;
@property (nonatomic, assign, nullable) CoinJoinClientOptions *options;
@property (nonatomic, assign) BOOL anonymizableTallyCachedNonDenom;
@property (nonatomic, assign) BOOL anonymizableTallyCached;
@property (nonatomic, strong) DSChain *chain;
@property (nonatomic, strong, nullable) DSCoinJoinWrapper *wrapper;
@property (nonatomic, readonly) BOOL isWaitingForNewBlock;
@property (nonatomic, readonly) BOOL isMixing;

- (instancetype)initWithChainManager:(DSChainManager *)chainManager;

- (BOOL)isMineInput:(UInt256)txHash index:(uint32_t)index;
- (NSArray<DSInputCoin *> *) availableCoins:(WalletEx *)walletEx onlySafe:(BOOL)onlySafe coinControl:(DSCoinControl *_Nullable)coinControl minimumAmount:(uint64_t)minimumAmount maximumAmount:(uint64_t)maximumAmount minimumSumAmount:(uint64_t)minimumSumAmount maximumCount:(uint64_t)maximumCount;
- (NSArray<DSCompactTallyItem *> *)selectCoinsGroupedByAddresses:(WalletEx *)walletEx skipDenominated:(BOOL)skipDenominated anonymizable:(BOOL)anonymizable skipUnconfirmed:(BOOL)skipUnconfirmed maxOupointsPerAddress:(int32_t)maxOupointsPerAddress;
- (uint32_t)countInputsWithAmount:(uint64_t)inputAmount;
- (NSString *)freshAddress:(BOOL)internal;
- (BOOL)commitTransactionForAmounts:(NSArray *)amounts outputs:(NSArray *)outputs onPublished:(void (^)(NSError * _Nullable error))onPublished;
- (DSSimplifiedMasternodeEntry *)masternodeEntryByHash:(UInt256)hash;
- (uint64_t)validMNCount;
- (DSMasternodeList *)mnList;
- (BOOL)isMasternodeOrDisconnectRequested;
- (void)sendAcceptMessage:(NSData *)message withPeerIP:(UInt128)address port:(uint16_t)port;
- (Balance *)getBalance;

- (void)startAsync;
- (void)stopAsync;
- (void)runCoinJoin;
- (BOOL)addPendingMasternode:(UInt256)proTxHash clientSessionId:(UInt256)sessionId;

@end

NS_ASSUME_NONNULL_END