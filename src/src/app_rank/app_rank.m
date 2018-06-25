#include <Foundation/Foundation.h>
#include <Foundation/NSJSONSerialization.h>
#import <objc/message.h>
#include "app_rank.h"
#include "HookUtil.h"
#include "Macro.h"
#include "logger/logger.m"
#include "mobile_gestalt/mobile_gestalt.h"

static id page_sections = nil;
static Class page;
static dispatch_source_t t_interval;
static NSString* app_rank_target_config = nil;
static int64_t limit_rank_num = 0;
static CFBooleanRef target_rank_found = false;

static unsigned long GetItemCount(){
  NSMutableArray* sections = [[NSMutableArray alloc] init];
  [sections addObjectsFromArray: [page_sections sections]];
  if (![sections count]) {
    return 0;
  }
  SKUIGridViewElementPageSection* section = [sections objectAtIndex:0];
  if (section!=nil) {
    return [section numberOfCells];
  }
  return 0;
}
static id GetSection(){
  NSMutableArray* sections = [[NSMutableArray alloc] init];
  [sections addObjectsFromArray: [page_sections sections]];
  return [sections objectAtIndex:0];
}
static int64_t GetNum(Class store){
  NSMutableArray* sections = [[NSMutableArray alloc] init];
  [sections addObjectsFromArray: [store sections]];
  Class grid = [sections objectAtIndex:0];
  return [grid numberOfCells];
}
static int64_t SetAppRankNo1(Class store,NSString* appid){
  int64_t result = -1;
  NSMutableArray* sections = [[NSMutableArray alloc] init];
  [sections addObjectsFromArray: [store sections]];
  Class grid = [sections objectAtIndex:0];
  int64_t max_apps = [grid numberOfCells];
  id target;
  for(int64_t index = 0; index < max_apps;index++){
    //AFLog(@"func:%s line:%d class:%@",__FUNCTION__,__LINE__,grid);
    id v4 = [grid class];
    //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
    Ivar v5 = class_getInstanceVariable(v4, "_viewElements");
    id v6 = object_getIvar(grid, v5);
    if (v6==nil||!v6) {
      break;
    }
    //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
    //Ivar grid_config_v1 = class_getClassVariable(grid, "_configuration");
    //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
    //id grid_config = object_getIvar(grid, grid_config_v1);
    //Class grid_config_v2 = object_getClass(grid_config);
    //AFLog(@"func:%s line:%d class:%@",__FUNCTION__,__LINE__,grid_config);
    //id grid_config_v3 = [grid_config_v2 class];
    //AFLog(@"func:%s line:%d class:%@",__FUNCTION__,__LINE__,grid_config_v3);
    //Ivar grid_config_v4 = class_getInstanceVariable(grid_config_v3, "_viewElements");
    //id grid_config_v5 = object_getIvar(grid_config, grid_config_v4);
    //id target_1 = [v6 objectAtIndex:index];
    //AFLog(@"func:%s line:%d class:%@ type:%@",__FUNCTION__,__LINE__,grid_config_v5,object_getClass(grid_config_v5));
    //AFLog(@"func:%s line:%d class:%@ type:%@",__FUNCTION__,__LINE__,grid_config_v5,object_getClass(v6));
    //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
    target = [v6 objectAtIndex:index];
    //AFLog(@"func:%s line:%d clss:%@",__FUNCTION__,__LINE__,target);
    id v8 = [target class];
    //AFLog(@"func:%s line:%d clss:%@",__FUNCTION__,__LINE__,object_getClass(v8));
    Ivar v9 = class_getInstanceVariable(v8, "_attributes");
    id v10 = object_getIvar(target, v9);
    if (v10==nil||!v10) {
      break;
    }
    //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
    NSString* v11 = [v10 objectForKey:@"data-content-id"];
    //AFLog(@"data-content-id=%@",v11);
    if(v11&&[v11 isEqualToString: appid]){
      if (index==0) {
        target_rank_found = kCFBooleanTrue;
        return index;
      }
      target_rank_found = kCFBooleanTrue;
      //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
      //[grid_config_v5 removeObjectAtIndex:index];
      //[grid_config_v5 replaceObjectAtIndex:0 withObject:target_1];
    
      //[v6 removeObjectAtIndex:index];//fix bug?
      [v6 replaceObjectAtIndex:0 withObject:target];
      //AFLog(@"func:%s line:%d target:%@ rank:%u",__FUNCTION__,__LINE__,target,index);
      [store _reloadCollectionView];
      //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
      return index;
    }
  }
  return result;
}
static void SetRankNo1(Class store){
  if (page_sections) {
    int64_t num = GetNum(store);
    struct CGPoint p = {.x = 0, .y = 0};
    static struct CGPoint p1 = {.x = 0.0, .y = 0};
    if (num>1&&num<limit_rank_num){
      //num<limit_rank_num
      //AFLog(@"func:%s line:%d num:%u class:%@",__FUNCTION__,__LINE__,num,app_rank_target_config);
      int64_t rank = SetAppRankNo1(store,app_rank_target_config);
      if (rank<=-1){
        if (!target_rank_found) {
          if (access("/tmp/rank_init.txt", F_OK)!=0) {
            FILE* fp = fopen("/tmp/rank_init.txt", "ab+");
            fclose(fp);
          }
          id v1 = [store class];
          Ivar v2 = class_getInstanceVariable(v1,"_collectionView");
          id v3 = object_getIvar(store,v2);
          //AFLog(@"func:%s line:%d class:%@",__FUNCTION__,__LINE__,v3);
          [store scrollViewWillEndDragging:v3 withVelocity:p targetContentOffset:&p1];
          [store scrollViewDidEndDragging:v3 willDecelerate:false];
          p1.y += 1000.0;
          return;
        }
      }
      else{
        FILE* fp = fopen("/tmp/rank.txt", "ab+");
        fclose(fp);
        target_rank_found = kCFBooleanFalse;
      }
      //AFLog(@"func:%s line:%d y:%f",__FUNCTION__,__LINE__,p1.y);
    }
    return;
  }
  return;
}
//[SKUIStorePageSectionsViewController - (id)collectionView:(id)arg1 cellForItemAtIndexPath:(id)arg2;]
_HOOK_MESSAGE(id,SKUIStorePageSectionsViewController,collectionView,id arg1,id arg2){
  //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
  id result;
  result = _SKUIStorePageSectionsViewController_collectionView(self,sel,arg1,arg2);
  page_sections = result;
  if (page_sections!=nil) {
    NSString* s = NSStringFromClass(object_getClass(result));
    if (s&&[s isEqual:@"SKUICollectionView"]) {
      //AFLog(@"func:%s line:%d class:%@",
      //      __FUNCTION__,__LINE__,object_getClass(result));
      page = object_getClass(result);
    }
    t_interval = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                        dispatch_get_main_queue());
    dispatch_source_set_timer(t_interval,
                              dispatch_walltime(NULL, 0 * NSEC_PER_SEC),
                              0.5 * NSEC_PER_SEC,0);
    dispatch_source_set_event_handler(t_interval, ^{
      SetRankNo1(self);
    });
    dispatch_resume(t_interval);
  }
  return result;
}
_HOOK_MESSAGE(void,SKUIStorePageSectionsViewController,scrollViewWillEndDragging,id arg1,struct CGPoint arg2,struct CGPoint* arg3){
  //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
  _SKUIStorePageSectionsViewController_scrollViewWillEndDragging(self,sel,arg1,arg2,arg3);
}
_HOOK_MESSAGE(id,SKUIStorePageSectionsViewController,viewWillAppear,bool arg1){
  //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
  id r = _SKUIStorePageSectionsViewController_viewWillAppear(self,sel,arg1);
  page_sections = r;
  //AFLog(@"func:%s line:%d class:%@ self:",
  //      __FUNCTION__,__LINE__,object_getClass(r));
  return r;
}
_HOOK_MESSAGE(id,SKUIStorePageSectionsViewController,viewWillDisappear,bool arg1){
  //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
  id r = _SKUIStorePageSectionsViewController_viewWillDisappear(self,sel,arg1);
  //AFLog(@"func:%s line:%d class:%@",
  //      __FUNCTION__,__LINE__,object_getClass(page_sections));
  page_sections = nil;
  if (t_interval) {
    dispatch_source_cancel(t_interval);
    t_interval = nil;
  }
  return r;
}
_HOOK_MESSAGE(id,SKUIStorePageSectionsViewController,dealloc){
  //AFLog(@"func:%s line:%d",__FUNCTION__,__LINE__);
  id r = _SKUIStorePageSectionsViewController_dealloc(self,sel);
  //AFLog(@"func:%s line:%d class:%@",
  //      __FUNCTION__,__LINE__,object_getClass(page_sections));
  page_sections = nil;
  if (t_interval) {
    dispatch_source_cancel(t_interval);
    t_interval = nil;
  }
  return r;
}
void InitAppRank(int arg_warring){
  CFTypeRef app_rank_target = GetConfigValue(@"APP_RANK_TARGET");
  CFTypeRef ranks = GetConfigValue(@"LIMIT_RANK_NUM");
  limit_rank_num = 0;
  CFNumberGetValue(ranks, kCFNumberSInt64Type, &limit_rank_num);
  app_rank_target_config = (NSString*)CFBridgingRelease(app_rank_target);
  if ([app_rank_target_config length]<=0) {
    app_rank_target_config = nil;
  }
  _Init_SKUIStorePageSectionsViewController_scrollViewWillEndDragging();
  _Init_SKUIStorePageSectionsViewController_viewWillDisappear();
  _Init_SKUIStorePageSectionsViewController_collectionView();
  _Init_SKUIStorePageSectionsViewController_viewWillAppear();
  _Init_SKUIStorePageSectionsViewController_dealloc();
}
