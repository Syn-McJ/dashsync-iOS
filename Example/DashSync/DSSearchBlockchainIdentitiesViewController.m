//  
//  Created by Sam Westrich
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DSSearchBlockchainIdentitiesViewController.h"
#import "DSBlockchainIdentitySearchTableViewCell.h"

@interface DSSearchBlockchainIdentitiesViewController ()

@property (nonatomic,strong) NSArray * blockchainIdentities;

@end

@implementation DSSearchBlockchainIdentitiesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.blockchainIdentities = [NSArray array];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.blockchainIdentities.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DSBlockchainIdentitySearchTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"BlockchainIdentityNameCellIdentifier" forIndexPath:indexPath];
    
    DSBlockchainIdentity * identity = self.blockchainIdentities[indexPath.row];
    
    cell.usernameLabel.text = identity.currentUsername;
    cell.identityUniqueIDLabel.text = identity.uniqueIdString;
    
    return cell;
}

-(void)searchByNamePrefix:(NSString*)namePrefix {
    [self.chainManager.identitiesManager searchIdentitiesByNamePrefix:namePrefix withCompletion:^(NSArray<DSBlockchainIdentity *> * _Nullable blockchainIdentities, NSError * _Nullable error) {
        if (!error) {
            self.blockchainIdentities = blockchainIdentities;
            [self.tableView reloadData];
        }
    }];
}

-(void)searchByIdentifier:(NSString*)identifier {
    [self.chainManager.identitiesManager searchIdentitiesByDPNSRegisteredBlockchainIdentityUniqueID:identifier withCompletion:^(NSArray<DSBlockchainIdentity *> * _Nullable blockchainIdentities, NSError * _Nullable error) {
        if (!error) {
            self.blockchainIdentities = blockchainIdentities;
            [self.tableView reloadData];
        }
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    if (!searchBar.selectedScopeButtonIndex) {
        [self searchByNamePrefix:searchBar.text];
    } else {
        [self searchByIdentifier:searchBar.text];
    }
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end