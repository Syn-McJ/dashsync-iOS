//  
//  Created by Sam Westrich
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

#import "DSPlatformQuery.h"
#import "DSPlatformTreeQuery.h"

@interface DSPlatformQuery()

@property(nonatomic, strong) NSDictionary<NSNumber*, DSPlatformTreeQuery*> * treeQueries;

@end

@implementation DSPlatformQuery

+(DSPlatformQuery*)platformQueryForIdentityID:(NSData*)identityID {
    DSPlatformQuery * query = [[DSPlatformQuery alloc] init];
    DSPlatformTreeQuery * identitiesQuery = [DSPlatformTreeQuery platformTreeQueryForKeys:@[identityID]];
    query.treeQueries = @{@(DSPlatformDictionary_Identities): identitiesQuery};
    return query;
}

-(DSPlatformTreeQuery*)treeQueryForType:(DSPlatformDictionary)treeType {
    return [self.treeQueries objectForKey:@(treeType)];
}

@end
