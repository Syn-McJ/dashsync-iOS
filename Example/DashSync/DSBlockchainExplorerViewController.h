//
//  DSBlockchainExplorerViewController.h
//  DashSync_Example
//
//  Created by Sam Westrich on 6/5/18.
//  Copyright © 2018 Andrew Podkovyrin. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <DashSync/DashSync.h>

@interface DSBlockchainExplorerViewController : UITableViewController <NSFetchedResultsControllerDelegate,UISearchBarDelegate>

@property (nonatomic,strong) DSChain * chain;

@end