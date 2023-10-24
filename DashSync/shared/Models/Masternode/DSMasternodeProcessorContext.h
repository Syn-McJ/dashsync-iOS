//
//  Created by Vladimir Pirogov
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "BigIntTypes.h"
#import "DSChain.h"
#import "DSMasternodeList.h"
#import "DSPeer.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef DSMasternodeList *_Nullable(^_Nullable MasternodeListFinder)(UInt256 blockHash);
typedef UInt256(^_Nullable MerkleRootFinder)(UInt256 blockHash);
typedef DSMerkleBlock *_Nullable(^_Nullable MerkleBlockFinder)(UInt256 blockHash);

@interface DSMasternodeProcessorContext : NSObject

@property (nonatomic) DSChain *chain;
@property (nonatomic, nullable) DSPeer *peer;
@property (nonatomic) BOOL useInsightAsBackup;
@property (nonatomic) BOOL isFromSnapshot;
@property (nonatomic) BOOL isDIP0024;
@property (nonatomic, copy) MasternodeListFinder masternodeListLookup;
@property (nonatomic, copy) BlockHeightFinder blockHeightLookup;
@property (nonatomic, copy) MerkleRootFinder merkleRootLookup;

- (BOOL)saveCLSignature:(UInt256)blockHash signature:(UInt768)signature;
- (void)blockUntilGetInsightForBlockHash:(UInt256)blockHash;

@end

NS_ASSUME_NONNULL_END
