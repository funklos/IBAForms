//
// Copyright 2010 Itty Bitty Apps Pty Ltd
// 
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this 
// file except in compliance with the License. You may obtain a copy of the License at 
// 
// http://www.apache.org/licenses/LICENSE-2.0 
// 
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF 
// ANY KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.
//

#import "IBAFormViewController.h"
#import "IBAFormConstants.h"
#import "IBAInputManager.h"

@interface IBAFormViewController ()
- (void)releaseViews;
- (void)makeFormFieldVisible:(IBAFormField *)formField;
- (void)registerForNotifications;
- (void)registerSelector:(SEL)selector withNotification:(NSString *)notificationKey;
- (void)adjustTableViewHeightForCoveringFrame:(CGRect)coveringFrame;
- (CGRect)rectForOrientationFrame:(CGRect)frame;

// Notification methods
- (void)pushViewController:(NSNotification *)notification;
- (void)presentModalViewController:(NSNotification *)notification;
- (void)dismissModalViewController:(NSNotification *)notification;

@end

@implementation IBAFormViewController

@synthesize tableView = tableView_;
@synthesize tableViewOriginalFrame = tableViewOriginalFrame_;
@synthesize formDataSource = formDataSource_;
@synthesize editingFormField = editingFormField_;

#pragma mark -
#pragma mark Initialisation and memory management

- (void)dealloc {
	[self releaseViews];
	IBA_RELEASE_SAFELY(formDataSource_);
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
    [super dealloc];
}

- (void)releaseViews {
	IBA_RELEASE_SAFELY(tableView_);
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil formDataSource:(IBAFormDataSource *)formDataSource {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
		self.formDataSource = formDataSource;
		self.hidesBottomBarWhenPushed = YES;
		
		[self registerForNotifications];
	}
	
    return self;
}

- (void)registerForNotifications {
	[self registerSelector:@selector(inputManagerWillShow:) withNotification:UIKeyboardWillShowNotification];
	[self registerSelector:@selector(inputManagerDidHide:) withNotification:UIKeyboardDidHideNotification];

	[self registerSelector:@selector(formFieldActivated:) withNotification:IBAInputRequestorFormFieldActivated];
	
	[self registerSelector:@selector(pushViewController:) withNotification:IBAPushViewController];
	[self registerSelector:@selector(presentModalViewController:) withNotification:IBAPresentModalViewController];
	[self registerSelector:@selector(dismissModalViewController:) withNotification:IBADismissModalViewController];
}

- (void)registerSelector:(SEL)selector withNotification:(NSString *)notificationKey {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:selector name:notificationKey object:nil];
}


- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    return [self initWithNibName:nibNameOrNil bundle:nibBundleOrNil formDataSource:nil];
}


#pragma mark -
#pragma mark View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
	
	self.tableView.dataSource = self.formDataSource;
	self.tableView.delegate = self;
	
	tableViewOriginalFrame_ = self.tableView.frame;
}

- (void)viewDidUnload {
	[self releaseViews];
	
	[super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	
	[[IBAInputManager sharedIBAInputManager] setInputRequestorDataSource:self];	
	
	// There is a bug with UIModalPresentationFormSheet where the keyboard won't dismiss even when there is
	// no first responder, so we remove the 'Done' button when UIModalPresentationFormSheet is used.
	BOOL displayDoneButton = (self.modalPresentationStyle != UIModalPresentationFormSheet);
	if (self.navigationController != nil) {
		displayDoneButton &= (self.navigationController.modalPresentationStyle != UIModalPresentationFormSheet);
	}
	
	[[[IBAInputManager sharedIBAInputManager] inputNavigationToolbar] setDisplayDoneButton:displayDoneButton];
		
	[self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];

	[[IBAInputManager sharedIBAInputManager] deactivateActiveInputRequestor];
	[[[IBAInputManager sharedIBAInputManager] inputNavigationToolbar] setDisplayDoneButton:YES];
	if ([[IBAInputManager sharedIBAInputManager] inputRequestorDataSource] == self) {
		[[IBAInputManager sharedIBAInputManager] setInputRequestorDataSource:nil];
	}
}

#pragma mark -
#pragma mark Property management

// this setter also sets the datasource of the tableView and reloads the table
- (void)setFormDataSource:(IBAFormDataSource *)dataSource {
	if (dataSource != formDataSource_) {
		IBAFormDataSource *oldDataSource = formDataSource_;
		formDataSource_ = [dataSource retain];
		IBA_RELEASE_SAFELY(oldDataSource);

		self.tableView.dataSource = formDataSource_;
		[self.tableView reloadData];
	}
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	IBAFormField *formField = [self.formDataSource formFieldAtIndexPath:indexPath];
	if ([formField hasDetailViewController]) {
		// The row has a detail view controller that we should push on to the navigation stack
		[[self navigationController] pushViewController:[formField detailViewController] animated:YES];
	} else if ([formField conformsToProtocol:@protocol(IBAInputRequestor)]){
		// Start editing the form field
		[[IBAInputManager sharedIBAInputManager] setActiveInputRequestor:(id<IBAInputRequestor>)formField];
	} else {
		[formField select];
	}
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	return [self.formDataSource viewForFooterInSection:section];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	return [self.formDataSource viewForHeaderInSection:section];
}

#pragma mark -
#pragma mark IBAInputRequestorDataSource

- (id<IBAInputRequestor>)nextInputRequestor:(id<IBAInputRequestor>)currentInputRequestor {
	// Return the next form field that supports inline editing
	IBAFormField *nextField = [self.formDataSource formFieldAfter:currentInputRequestor];
	while ((nextField != nil) && (![nextField conformsToProtocol:@protocol(IBAInputRequestor)])) {
		nextField = [self.formDataSource formFieldAfter:nextField];
	}
	
	return (id<IBAInputRequestor>)nextField;
}


- (id<IBAInputRequestor>)previousInputRequestor:(id<IBAInputRequestor>)currentInputRequestor {
	// Return the previous form field that supports inline editing
	IBAFormField *previousField = [self.formDataSource formFieldBefore:currentInputRequestor];
	while ((previousField != nil) && (![previousField conformsToProtocol:@protocol(IBAInputRequestor)])) {
		previousField = [self.formDataSource formFieldBefore:previousField];
	}
	
	return (id<IBAInputRequestor>)previousField;
}


#pragma mark -
#pragma mark Responses to IBAInputManager notifications

- (void)inputManagerWillShow:(NSNotification *)notification {
	NSDictionary* info = [notification userInfo];
	CGRect keyboardFrame = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
	[self adjustTableViewHeightForCoveringFrame:[self rectForOrientationFrame:keyboardFrame]];
}

- (void)inputManagerDidHide:(NSNotification *)notification {
	[self adjustTableViewHeightForCoveringFrame:CGRectZero];
}

- (void)formFieldActivated:(NSNotification *)notification {
	IBAFormField *formField = [[notification userInfo] objectForKey:IBAFormFieldKey];
	if (formField != nil) {
		[self makeFormFieldVisible:formField];
		if ([formField hasDetailViewController]) {
			// The form field has a detail view controller that we should push on to the navigation stack
			[[self navigationController] pushViewController:[formField detailViewController] animated:YES];
		}
	}
}

#pragma mark -
#pragma mark Size and visibility accommodations for the input manager view

- (void)makeFormFieldVisible:(IBAFormField *)formField {
	NSIndexPath *formFieldIndexPath = [self.formDataSource indexPathForFormField:formField];
	[self.tableView scrollToRowAtIndexPath:formFieldIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
}

- (void)adjustTableViewHeightForCoveringFrame:(CGRect)coveringFrame {
	CGRect normalisedWindowBounds = [self rectForOrientationFrame:[[[UIApplication sharedApplication] keyWindow] bounds]];
	CGRect normalisedTableViewFrame = [self rectForOrientationFrame:[self.tableView convertRect:self.tableView.bounds 
																						 toView:self.tableView.window]];
	[UIView animateWithDuration:0.2 
					 animations: ^(void){
						UIEdgeInsets contentInsets = UIEdgeInsetsMake(0, 0, coveringFrame.size.height - (normalisedWindowBounds.size.height - CGRectGetMaxY(normalisedTableViewFrame)), 0);
						// NSLog(@"UIEdgeInsets contentInsets bottom %f", contentInsets.bottom);
						self.tableView.contentInset = contentInsets;
						self.tableView.scrollIndicatorInsets = contentInsets;
					 }
					 completion: ^(BOOL finished){
						 self.tableView.scrollEnabled = YES;
						 [self.tableView flashScrollIndicators];
					 }];
}


#pragma mark -
#pragma mark Push view controller requests

- (void)pushViewController:(NSNotification *)notification {
	UIViewController *viewController = [[notification userInfo] objectForKey:IBAViewControllerKey];
	if (viewController != nil) {
		[[self navigationController] pushViewController:viewController animated:YES];
	}
}


#pragma mark -
#pragma mark Present modal view controller requests

- (void)presentModalViewController:(NSNotification *)notification {
	UIViewController *viewController = [[notification userInfo] objectForKey:IBAViewControllerKey];
	if (viewController != nil) {
		[self presentModalViewController:viewController animated:YES];
	}
}

- (void)dismissModalViewController:(NSNotification *)notification; {
	[self dismissModalViewControllerAnimated:YES];
}

#pragma mark -
#pragma mark Misc

- (CGFloat)tableView:(UITableView *)aTableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [self.formDataSource tableView:aTableView cellForRowAtIndexPath:indexPath];
	[cell sizeToFit];
	return cell.bounds.size.height;
}

- (CGRect)rectForOrientationFrame:(CGRect)frame {
	if (UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation])) {
		return frame;
	}
	else
	{
		return CGRectMake(frame.origin.y, frame.origin.x, frame.size.height, frame.size.width);
	}	
}

@end
