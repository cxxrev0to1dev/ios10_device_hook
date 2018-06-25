#ifndef APP_BANK_H_
#define APP_BANK_H_

#include <Foundation/Foundation.h>
#include "HookUtil.h"
#include "Macro.h"
#include <Foundation/NSJSONSerialization.h>

@interface SKUIStorePageSectionsViewController
@property (readonly) Class superclass;
+ (bool)_shouldForwardViewWillTransitionToSize;
+ (id)viewControllerWithRestorationIdentifierPath:(id)arg1 coder:(id)arg2;
- (id)SKUIStackedBar;
- (void)_applyColorScheme:(id)arg1 toIndexBarControl:(id)arg2;
- (void)_beginActiveImpressionsForImpressionableViewElements;
- (void)_beginIgnoringSectionChanges;
- (id)_childSectionsForMenuComponent:(id)arg1 selectedIndex:(long long)arg2;
- (id)_collectionViewSublayouts;
- (void)_contentSizeChangeNotification:(id)arg1;
- (id)_createSectionsForExpandPageComponent:(id)arg1 context:(id)arg2 newSections:(id)arg3 sectionCount:(long long)arg4 sectionsByViewElement:(id)arg5 updateStyle:(long long)arg6;
- (id)_currentBackdropGroupName;
- (id)_defaultSectionForGridComponent:(id)arg1;
- (id)_defaultSectionForSwooshComponent:(id)arg1;
- (void)_deselectCellsForAppearance:(bool)arg1;
- (void)_endAllPendingActiveImpression;
- (void)_endIgnoringSectionChanges;
- (void)_entityProviderDidInvalidateNotification:(id)arg1;
- (void)_enumerateSectionContextsUsingBlock:(id /* block */)arg1;
- (void)_enumerateVisibleSectionsUsingBlock:(id /* block */)arg1;
- (id)_expandContextForMenuComponent:(id)arg1;
- (void)_handleTap:(id)arg1;
- (id)_impressionableViewElements;
- (void)_insertSectionsWithComponents:(id)arg1 afterSection:(id)arg2;
- (void)_invalidateIfLastKnownWidthChanged;
- (void)_invalidateLayoutWithNewSize:(struct CGSize { double x1; double x2; })arg1 transitionCoordinator:(id)arg2;
- (void)_longPressAction:(id)arg1;
- (id)_menuContextForMenuComponent:(id)arg1;
- (id)_newSectionContext;
- (id)_newSectionsWithPageComponent:(id)arg1;
- (id)_newSectionsWithPageComponents:(id)arg1;
- (id)_newStorePageCollectionViewLayout;
- (void)_pageSectionDidDismissOverlayController:(id)arg1;
- (void)_prefetchArtworkForVisibleSections;
- (id)_prepareLayoutForSections;
- (void)_registerForNotificationsForEntityProvider:(id)arg1;
- (void)_reloadCollectionView;
- (void)_reloadRelevantEntityProviders;
- (void)_scrollFirstAppearanceSectionToView;
- (void)_setActiveProductPageOverlayController:(id)arg1;
- (void)_setPageSize:(struct CGSize { double x1; double x2; })arg1;
- (void)_setRendersWithParallax:(bool)arg1;
- (void)_setRendersWithPerspective:(bool)arg1;
- (void)_setSelectedIndex:(long long)arg1 forMenuSection:(id)arg2;
- (id)_splitForSectionIndex:(long long)arg1;
- (void)_startRefresh:(id)arg1;
- (id)_textLayoutCache;
- (void)_unregisterForNotificationsForEntityProvider:(id)arg1;
- (void)_updateCollectionViewWithUpdates:(id /* block */)arg1;
- (void)_updateSectionsAfterMenuChange;
- (void)_updateSectionsForIndex:(long long)arg1 menuSection:(id)arg2;
- (id)_visibleMetricsImpressionsString;
- (id)activeMetricsImpressionSession;
- (id)backgroundColorForSection:(long long)arg1;
- (id)collectionView;
- (bool)collectionView:(id)arg1 canScrollCellAtIndexPath:(id)arg2;
- (id)collectionView:(id)arg1 cellForItemAtIndexPath:(id)arg2;
- (void)collectionView:(id)arg1 didConfirmButtonElement:(id)arg2 withClickInfo:(id)arg3 forItemAtIndexPath:(id)arg4;
- (void)collectionView:(id)arg1 didEndDisplayingCell:(id)arg2 forItemAtIndexPath:(id)arg3;
- (void)collectionView:(id)arg1 didEndEditingItemAtIndexPath:(id)arg2;
- (void)collectionView:(id)arg1 didSelectItemAtIndexPath:(id)arg2;
- (void)collectionView:(id)arg1 editorialView:(id)arg2 didSelectLink:(id)arg3;
- (void)collectionView:(id)arg1 expandEditorialForLabelElement:(id)arg2 indexPath:(id)arg3;
- (long long)collectionView:(id)arg1 layout:(id)arg2 pinningStyleForItemAtIndexPath:(id)arg3;
- (long long)collectionView:(id)arg1 layout:(id)arg2 pinningTransitionStyleForItemAtIndexPath:(id)arg3;
- (void)collectionView:(id)arg1 layout:(id)arg2 willApplyLayoutAttributes:(id)arg3;
- (long long)collectionView:(id)arg1 numberOfItemsInSection:(long long)arg2;
- (void)collectionView:(id)arg1 performDefaultActionForViewElement:(id)arg2 indexPath:(id)arg3;
- (bool)collectionView:(id)arg1 shouldHighlightItemAtIndexPath:(id)arg2;
- (bool)collectionView:(id)arg1 shouldSelectItemAtIndexPath:(id)arg2;
- (void)collectionView:(id)arg1 willBeginEditingItemAtIndexPath:(id)arg2;
- (void)collectionView:(id)arg1 willDisplayCell:(id)arg2 forItemAtIndexPath:(id)arg3;
- (id)colorScheme;
- (void)dealloc;
- (void)decodeRestorableStateWithCoder:(id)arg1;
- (id)defaultSectionForComponent:(id)arg1;
- (id)delegate;
- (void)dismissOverlays;
- (void)encodeRestorableStateWithCoder:(id)arg1;
- (id)indexBarControl;
- (id)indexPathsForGradientItemsInCollectionView:(id)arg1 layout:(id)arg2;
- (id)indexPathsForPinningItemsInCollectionView:(id)arg1 layout:(id)arg2;
- (id)initWithCoder:(id)arg1;
- (id)initWithLayoutStyle:(long long)arg1;
- (id)initWithNibName:(id)arg1 bundle:(id)arg2;
- (void)invalidateAndReload;
- (bool)isDisplayingOverlays;
- (void)itemCollectionView:(id)arg1 didConfirmItemOfferForCell:(id)arg2;
- (void)itemCollectionView:(id)arg1 didTapVideoForCollectionViewCell:(id)arg2;
- (void)itemStateCenter:(id)arg1 itemStatesChanged:(id)arg2;
- (void)layoutCacheDidFinishBatch:(id)arg1;
- (void)loadView;
- (id)metricsController;
- (long long)numberOfSectionsInCollectionView:(id)arg1;
- (bool)performTestWithName:(id)arg1 options:(id)arg2;
- (long long)pinningTransitionStyle;
- (void)previewingContext:(id)arg1 commitViewController:(id)arg2;
- (id)previewingContext:(id)arg1 viewControllerForLocation:(struct CGPoint { double x1; double x2; })arg2;
- (void)productPageOverlayDidDismiss:(id)arg1;
- (id)pullToRefreshDelegate;
- (void)reloadSections:(id)arg1;
- (id)resourceLoader;
- (void)scrollViewDidEndDecelerating:(id)arg1;
- (void)scrollViewDidEndDragging:(id)arg1 willDecelerate:(bool)arg2;
- (void)scrollViewDidScroll:(id)arg1;
- (void)scrollViewWillEndDragging:(id)arg1 withVelocity:(struct CGPoint { double x1; double x2; })arg2 targetContentOffset:(inout struct CGPoint { double x1; double x2; }*)arg3;
- (id)sections;
- (void)setActiveMetricsImpressionSession:(id)arg1;
- (void)setColorScheme:(id)arg1;
- (void)setDelegate:(id)arg1;
- (void)setIndexBarControl:(id)arg1;
- (void)setMetricsController:(id)arg1;
- (void)setPinningTransitionStyle:(long long)arg1;
- (void)setPullToRefreshDelegate:(id)arg1;
- (void)setResourceLoader:(id)arg1;
- (void)setSKUIStackedBar:(id)arg1;
- (void)setSectionsWithPageComponents:(id)arg1;
- (void)setSectionsWithSplitsDescription:(id)arg1;
- (void)setUsePullToRefresh:(bool)arg1;
- (void)showOverlayWithProductPage:(id)arg1 metricsPageEvent:(id)arg2;
- (void)skuiCollectionViewWillLayoutSubviews:(id)arg1;
- (void)skui_viewWillAppear:(bool)arg1;
- (void)viewDidAppear:(bool)arg1;
- (void)viewDidDisappear:(bool)arg1;
- (void)viewWillAppear:(bool)arg1;
- (void)viewWillDisappear:(bool)arg1;
- (void)viewWillTransitionToSize:(struct CGSize { double x1; double x2; })arg1 withTransitionCoordinator:(id)arg2;
- (void)willPresentPreviewViewController:(id)arg1 forLocation:(struct CGPoint { double x1; double x2; })arg2 inSourceView:(id)arg3;

@end

@interface SKUIGridViewElementPageSection
- (long long)numberOfCells;
@end

@interface SKUICollectionView
- (void)setContentOffset:(struct CGPoint { double x1; double x2; })arg1 animated:(bool)arg2;
@end

void InitAppRank(int arg_warring);

#endif
