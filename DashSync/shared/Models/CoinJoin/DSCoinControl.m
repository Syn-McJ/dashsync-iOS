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

#import "DSCoinControl.h"

@implementation DSCoinControl

- (instancetype)initWithFFICoinControl:(CoinControl *)coinControl {
    if (!(self = [super init])) return nil;
    self.coinType = coinControl->coin_type;
    self.minDepth = coinControl->min_depth;
    self.maxDepth = coinControl->max_depth;
    self.avoidAddressReuse = coinControl->avoid_address_reuse;
    self.allowOtherInputs = coinControl->allow_other_inputs;
    
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _setSelected = [[NSMutableOrderedSet alloc] init];
        _coinType = CoinType_AllCoins;
        _allowOtherInputs = NO;
        _requireAllInputs = NO;
        _allowWatchOnly = NO;
        _overrideFeeRate = NO;
        _avoidPartialSpends = NO;
        _avoidAddressReuse = NO;
        _minDepth = 0;
    }
    return self;
}

- (BOOL)hasSelected {
    return self.setSelected.count > 0;
}

- (BOOL)isSelected:(NSValue *)output {
    return [self.setSelected containsObject:output];
}

- (void)select:(NSValue *)output {
    [self.setSelected addObject:output];
}

- (void)unSelect:(NSValue *)output {
    [self.setSelected removeObject:output];
}

- (void)unSelectAll {
    [self.setSelected removeAllObjects];
}

- (void)useCoinJoin:(BOOL)useCoinJoin {
    self.coinType = useCoinJoin ? CoinType_OnlyFullyMixed : CoinType_AllCoins;
}

- (BOOL)isUsingCoinJoin {
    return self.coinType == CoinType_OnlyFullyMixed;
}

@end
