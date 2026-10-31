// MeineKit.m — Meine customizer (theme máy ảnh / vòng+huy hiệu / ảnh bìa profile)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreImage/CoreImage.h>

#define kPrefTheme  @"MeineTheme"
#define kPrefRing   @"MeineRing"
#define kPrefCover  @"MeineCover"
#define kPrefShift  @"MeineAvatarShift"
#define kNote       @"MeineSelectionChanged"
#define kTagCam  771001
#define kTagCover 771002
#define kTagRingBox 771003
#define kTagRingImg 771005
#define kTagBadgeImg 771006
#define kTagScan 771007

static BOOL MLogOn(void){ return [[NSUserDefaults standardUserDefaults] boolForKey:@"MeineLog"]; }
#define MLog(fmt,...) do{ if(MLogOn()) NSLog(@"[Meine] " fmt, ##__VA_ARGS__); }while(0)

static NSBundle *MBundle(void){
  static NSBundle *b=nil; static dispatch_once_t once;
  dispatch_once(&once,^{
    NSString *p=[[NSBundle mainBundle] pathForResource:@"Meine" ofType:@"bundle"];
    b=p?[NSBundle bundleWithPath:p]:nil;
    MLog(@"bundle=%@",p);
  });
  return b;
}
static NSString *MPath(NSString *rel){
  NSString *base=[MBundle() bundlePath]; if(!base) return nil;
  NSString *p=[base stringByAppendingPathComponent:rel];
  return [[NSFileManager defaultManager] fileExistsAtPath:p]?p:nil;
}
static UIImage *MImg(NSString *rel){ NSString *p=MPath(rel); return p?[UIImage imageWithContentsOfFile:p]:nil; }

// ---------- catalog ----------
static NSArray *MSubdirs(NSString *rel){
  NSString *base=[MBundle() bundlePath]; if(!base) return @[];
  NSString *dir=[base stringByAppendingPathComponent:rel];
  NSArray *c=[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]
              sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *out=[NSMutableArray array];
  for(NSString *n in c){ BOOL isDir=NO; NSString *p=[dir stringByAppendingPathComponent:n];
    if([[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&isDir] && isDir) [out addObject:n]; }
  return out;
}
static NSDictionary *MJSON(NSString *rel){
  NSString *p=MPath(rel); if(!p) return @{};
  NSData *d=[NSData dataWithContentsOfFile:p]; if(!d) return @{};
  id o=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
  return [o isKindOfClass:NSDictionary.class]?o:@{};
}
static NSArray *MThemes(void){
  static NSArray *a=nil; static dispatch_once_t once;
  dispatch_once(&once,^{ NSMutableArray *m=[NSMutableArray array];
    for(NSString *d in MSubdirs(@"themes")){
      NSDictionary *j=MJSON([NSString stringWithFormat:@"themes/%@/theme.json",d]);
      [m addObject:@{@"id":j[@"id"]?:d, @"name":j[@"name"]?:d,
        @"thumb":[NSString stringWithFormat:@"themes/%@/thumbnail.png",d],
        @"frame":[NSString stringWithFormat:@"themes/%@/frame.png",d]}]; }
    a=m; MLog(@"themes=%lu",(unsigned long)a.count); });
  return a;
}
static NSArray *MRings(void){
  static NSArray *a=nil; static dispatch_once_t once;
  dispatch_once(&once,^{ NSMutableArray *m=[NSMutableArray array];
    for(NSString *d in MSubdirs(@"vong-huy-hieu")){
      NSDictionary *j=MJSON([NSString stringWithFormat:@"vong-huy-hieu/%@/set.json",d]);
      [m addObject:@{@"id":j[@"id"]?:d, @"name":j[@"name"]?:d,
        @"ring":[NSString stringWithFormat:@"vong-huy-hieu/%@/ring.png",d],
        @"badge":[NSString stringWithFormat:@"vong-huy-hieu/%@/badge.png",d]}]; }
    a=m; MLog(@"rings=%lu",(unsigned long)a.count); });
  return a;
}
static NSDictionary *MFindItem(NSArray *arr, NSString *i){
  if(!i.length) return nil;
  for(NSDictionary *d in arr) if([d[@"id"] isEqualToString:i]) return d;
  return nil;
}

// ---------- utils ----------
static IMP MSwizzle(Class c, SEL s, IMP rep){
  Method m=class_getInstanceMethod(c,s); if(!m) return NULL;
  IMP o=method_getImplementation(m); method_setImplementation(m,rep); return o;
}
static NSString *MViewText(UIView *v){
  if(!v) return nil; NSMutableString *out=[NSMutableString string];
  void (^walk)(UIView*,int)=nil; walk=^(UIView *x,int depth){
    if(depth>5||out.length>200) return;
    if([x isKindOfClass:UILabel.class]){ NSString *t=((UILabel*)x).text; if(t.length) [out appendFormat:@" %@ ",t]; }
    if([x isKindOfClass:UIButton.class]){ NSString *t=[(UIButton*)x titleForState:UIControlStateNormal]; if(t.length) [out appendFormat:@" %@ ",t]; }
    for(UIView *c in x.subviews) walk(c,depth+1);
  }; walk(v,0); return out;
}
static BOOL MIsControlish(UIView *v){
  if([v isKindOfClass:UIControl.class]) return YES;
  NSString *n=NSStringFromClass(v.class);
  for(NSString *k in @[@"Button",@"Control",@"Capture",@"Shutter",@"Toolbar",@"TabBar",@"Sheet"])
    if([n rangeOfString:k].location!=NSNotFound) return YES;
  for(UIView *c in v.subviews) if([c isKindOfClass:UIControl.class]) return YES;
  return NO;
}
static UIView *MFindClass(UIView *root, NSString *cls){
  if(!root) return nil;
  if([NSStringFromClass(root.class) isEqualToString:cls]) return root;
  for(UIView *c in root.subviews){ UIView *r=MFindClass(c,cls); if(r) return r; }
  return nil;
}
static UITableView *MFindTable(UIView *root){
  if(!root) return nil;
  if([root isKindOfClass:UITableView.class]) return (UITableView*)root;
  for(UIView *c in root.subviews){ UITableView *t=MFindTable(c); if(t) return t; }
  return nil;
}
static UIImage *MBlur(UIImage *img, CGFloat radius){
  static CIContext *ctx=nil; static dispatch_once_t once;
  dispatch_once(&once,^{ ctx=[CIContext contextWithOptions:nil]; });
  CIImage *in=[CIImage imageWithCGImage:img.CGImage];
  CIFilter *f=[CIFilter filterWithName:@"CIGaussianBlur"];
  [f setValue:in forKey:kCIInputImageKey]; [f setValue:@(radius) forKey:kCIInputRadiusKey];
  CIImage *o=f.outputImage; if(!o) return img;
  CGRect r=in.extent;
  CGImageRef cg=[ctx createCGImage:o fromRect:r];
  if(!cg) return img;
  UIImage *out=[UIImage imageWithCGImage:cg scale:img.scale orientation:UIImageOrientationUp];
  CGImageRelease(cg); return out;
}
// ---------- selection storage ----------
static NSString *MKey(NSString *which){ return [@"meine." stringByAppendingString:which]; }
static NSString *MSelected(NSString *which){
  NSString *v=[[NSUserDefaults standardUserDefaults] stringForKey:MKey(which)];
  if(!v.length) return nil; return v;
}
static void MSetSelected(NSString *which, NSString *val){
  NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
  if(val) [d setObject:val forKey:MKey(which)]; else [d removeObjectForKey:MKey(which)];
  [d synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:MKey(which) object:nil];
}
static NSDictionary *MItem(NSString *which, NSString *sid){
  return MFindItem([which isEqualToString:@"ring"]?MRings():MThemes(), sid);
}
static NSString *MNameOf(NSString *which, NSString *sid){
  NSDictionary *it=MItem(which,sid); return it?it[@"name"]:sid;
}
static UIImage *MThumbFor(NSString *which, NSString *sid, CGSize size){
  if(!sid.length) return nil;
  NSDictionary *it=MItem(which,sid); if(!it) return nil;
  NSString *rel=[which isEqualToString:@"ring"]?it[@"ring"]:it[@"thumb"];
  UIImage *im=MImg(rel); if(!im) return nil;
  UIGraphicsBeginImageContextWithOptions(size, NO, 0);
  [im drawInRect:CGRectMake(0,0,size.width,size.height)];
  UIImage *o=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
  return o;
}

// ---------- cell / banner ----------
@interface MChoiceCell : UITableViewCell
@property(nonatomic,strong) UILabel *titleL; @property(nonatomic,strong) UIImageView *iv;
@end
@implementation MChoiceCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid{
  self=[super initWithStyle:style reuseIdentifier:rid]; if(!self) return nil;
  self.backgroundColor=UIColor.clearColor;
  self.titleL=[UILabel new]; self.titleL.font=[UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
  self.titleL.textColor=UIColor.whiteColor; self.titleL.translatesAutoresizingMaskIntoConstraints=NO;
  [self.contentView addSubview:self.titleL];
  self.iv=[UIImageView new]; self.iv.contentMode=UIViewContentModeScaleAspectFit;
  self.iv.layer.cornerRadius=7; self.iv.layer.masksToBounds=YES;
  self.iv.translatesAutoresizingMaskIntoConstraints=NO;
  [self.contentView addSubview:self.iv];
  [NSLayoutConstraint activateConstraints:@[
    [self.titleL.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
    [self.titleL.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.iv.widthAnchor constraintEqualToConstant:32],
    [self.iv.heightAnchor constraintEqualToConstant:32],
    [self.titleL.trailingAnchor constraintLessThanOrEqualToAnchor:self.iv.leadingAnchor constant:-8],
    [self.iv.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],
    [self.iv.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]
  ]];
  return self;
}
@end

// ---------- picker (grid chọn theme / vòng) ----------
@interface MPicker : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property(nonatomic,copy) NSString *which; @property(nonatomic,strong) UICollectionView *cv;
@property(nonatomic,strong) NSArray *items;
@end
@implementation MPicker
- (instancetype)initWithWhich:(NSString *)w{
  self=[super init]; if(!self) return nil; self.which=w; return self;
}
- (void)viewDidLoad{
  [super viewDidLoad];
  self.view.backgroundColor=[UIColor colorWithRed:0.06 green:0.06 blue:0.07 alpha:1];
  self.title=[self.which isEqualToString:@"ring"]?@"Vòng & huy hiệu":@"Theme máy ảnh";
  UICollectionViewFlowLayout *fl=[UICollectionViewFlowLayout new];
  fl.scrollDirection=UICollectionViewScrollDirectionVertical;
  fl.minimumInteritemSpacing=10; fl.minimumLineSpacing=14;
  fl.sectionInset=UIEdgeInsetsMake(16,16,16,16);
  self.cv=[[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:fl];
  self.cv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
  self.cv.backgroundColor=UIColor.clearColor;
  self.cv.dataSource=self; self.cv.delegate=self;
  [self.cv registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"c"];
  [self.view addSubview:self.cv];
  NSMutableArray *m=[NSMutableArray arrayWithObject:@{@"id":@"", @"name":@"Không dùng", @"__off":@1}];
  [m addObjectsFromArray:([self.which isEqualToString:@"ring"]?MRings():MThemes())];
  self.items=m;
  self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(mclose)];
}
- (void)mclose{ [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s{ return (NSInteger)self.items.count; }
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv{ return 1; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip{
  UICollectionViewCell *c=[cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
  c.backgroundColor=[UIColor colorWithWhite:1 alpha:0.06];
  c.layer.cornerRadius=14; c.layer.masksToBounds=YES;
  UIImageView *iv=(UIImageView*)[c viewWithTag:99];
  if(!iv){ iv=[UIImageView new]; iv.tag=99; iv.contentMode=UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints=NO; [c addSubview:iv];
    UILabel *lb=[UILabel new]; lb.tag=98; lb.font=[UIFont systemFontOfSize:11];
    lb.textColor=[UIColor colorWithWhite:1 alpha:0.85]; lb.numberOfLines=2;
    lb.textAlignment=NSTextAlignmentCenter; lb.translatesAutoresizingMaskIntoConstraints=NO; [c addSubview:lb];
    UILabel *ck=[UILabel new]; ck.tag=97; ck.font=[UIFont systemFontOfSize:18];
    ck.textColor=[UIColor colorWithRed:0.45 green:0.85 blue:1 alpha:1];
    ck.translatesAutoresizingMaskIntoConstraints=NO; [c addSubview:ck];
    [NSLayoutConstraint activateConstraints:@[
      [iv.topAnchor constraintEqualToAnchor:c.topAnchor constant:8],
      [iv.centerXAnchor constraintEqualToAnchor:c.centerXAnchor],
      [iv.widthAnchor constraintEqualToAnchor:c.widthAnchor constant:-16],
      [iv.heightAnchor constraintEqualToAnchor:iv.widthAnchor multiplier:[self.which isEqualToString:@"ring"]?1.0:1.6],
      [lb.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:4],
      [lb.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:4],
      [lb.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-4],
      [lb.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-6],
      [ck.topAnchor constraintEqualToAnchor:c.topAnchor constant:2],
      [ck.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-6]
    ]];
  }
  NSDictionary *it=self.items[(NSUInteger)ip.item];
  ((UILabel*)[c viewWithTag:98]).text=it[@"name"];
  NSString *sid=it[@"id"];
  BOOL off=[it[@"__off"] boolValue];
  NSString *sel=MSelected(self.which);
  BOOL isSel=(off? !sel.length : (sel && [sel isEqualToString:sid]));
  ((UILabel*)[c viewWithTag:97]).text=isSel?@"✓":@"";
  UIImageView *ivv=(UIImageView*)[c viewWithTag:99];
  if(off){ ivv.image=nil; }
  else {
    NSString *rel=[self.which isEqualToString:@"ring"]?it[@"ring"]:it[@"thumb"];
    ivv.image=MImg(rel);
  }
  return c;
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip{
  CGFloat w=(cv.bounds.size.width-32-20)/3.0;
  return CGSizeMake(w,[self.which isEqualToString:@"ring"]?w+30:w*1.6+34);
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip{
  NSDictionary *it=self.items[(NSUInteger)ip.item];
  BOOL off=[it[@"__off"] boolValue];
  MSetSelected(self.which, off?nil:it[@"id"]);
  [self dismissViewControllerAnimated:YES completion:nil];
}
@end

// ---------- settings table: thêm section "Cá nhân hoá" ----------
static const void *kMyTbl=&kMyTbl; static const void *kOrigN=&kOrigN; static const void *kDone=&kDone;
static NSMutableDictionary *MOrig(void){ static NSMutableDictionary *d; static dispatch_once_t o;
  dispatch_once(&o,^{d=[NSMutableDictionary new];}); return d; }
static NSString *MKeyC(Class c){ return NSStringFromClass(c); }
static IMP MOrigGet(Class c, SEL s){
  NSString *cn=MKeyC(c); while(c){
    NSString *n=MKeyC(c);
    NSDictionary *dd=MOrig()[n];
    NSValue *v=dd[NSStringFromSelector(s)];
    if(v) return (IMP)[v pointerValue];
    c=class_getSuperclass(c);
  }
  (void)cn; return NULL;
}
static void MOrigSet(Class c, SEL s, IMP i){
  NSString *n=MKeyC(c);
  NSMutableDictionary *dd=MOrig()[n]; if(!dd){ dd=[NSMutableDictionary new]; MOrig()[n]=dd; }
  dd[NSStringFromSelector(s)]=[NSValue valueWithPointer:i];
}
// gắn hk vào class c cho selector sel: orig (nếu có) lưu vào MOrig
static BOOL MInstall(Class c, SEL s, IMP hk, const char *types){
  if(!c || !s || !hk) return NO;
  Method m=class_getInstanceMethod(c,s);
  if(!m){ // không có ở cả c lẫn super → an toàn thêm mới
    BOOL ok=class_addMethod(c,s,hk,types);
    if(ok) MOrigSet(c,s,NULL);
    return ok;
  }
  IMP orig=method_getImplementation(m);
  if(MOrigGet(c,s)) return NO; // đã hook rồi
  MOrigSet(c,s,orig);
  // c có method riêng không? Thử thêm override của c trước
  if(class_addMethod(c,s,hk,types)) return YES;   // impl hiện ở super → thêm bản riêng cho c
  Method own=class_getInstanceMethod(c,s);
  method_setImplementation(own,hk);
  return YES;
}
static BOOL MIsMyTable(UITableView *tv){ return tv && objc_getAssociatedObject(tv,kMyTbl); }
static NSInteger MOrigN(UITableView *tv){
  NSNumber *n=objc_getAssociatedObject(tv,kOrigN); return n?n.integerValue:0;
}
static UIViewController *MVCFor(UIView *v){
  UIResponder *r=v; while(r){ if([r isKindOfClass:UIViewController.class]) return (UIViewController*)r; r=r.nextResponder; }
  UIWindow *w=v.window; UIViewController *top=w.rootViewController;
  while(top.presentedViewController) top=top.presentedViewController;
  return top;
}
static void MPresentPicker(UIViewController *from, NSString *which){
  if(!from) return;
  MPicker *p=[[MPicker alloc] initWithWhich:which];
  UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:p];
  nav.modalPresentationStyle=UIModalPresentationPageSheet;
  if(nav.sheetPresentationController){
    nav.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.largeDetent];
    nav.sheetPresentationController.prefersGrabberVisible=YES;
  }
  [from presentViewController:nav animated:YES completion:nil];
}

// --- wrappers ---
static NSInteger hk_numSec(id ds, SEL s, UITableView *tv){
  NSInteger (*o)(id,SEL,UITableView*)=(void*)MOrigGet(object_getClass(ds),s);
  NSInteger n=o?o(ds,s,tv):1;
  if(MIsMyTable(tv)){
    objc_setAssociatedObject(tv,kOrigN,@(n),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return n+1;
  }
  return n;
}
static NSInteger hk_rows(id ds, SEL s, UITableView *tv, NSInteger sec){
  NSInteger (*o)(id,SEL,UITableView*,NSInteger)=(void*)MOrigGet(object_getClass(ds),s);
  NSInteger n=o?o(ds,s,tv,sec):0;
  if(MIsMyTable(tv) && sec==MOrigN(tv)) return 2;
  return n;
}
static id hk_header(id ds, SEL s, UITableView *tv, NSInteger sec){
  id (*o)(id,SEL,UITableView*,NSInteger)=(void*)MOrigGet(object_getClass(ds),s);
  if(MIsMyTable(tv) && sec==MOrigN(tv)) return @"Cá nhân hoá";
  return o?o(ds,s,tv,sec):nil;
}
static id hk_cell(id ds, SEL s, UITableView *tv, NSIndexPath *ip){
  id (*o)(id,SEL,UITableView*,NSIndexPath*)=(void*)MOrigGet(object_getClass(ds),s);
  if(MIsMyTable(tv) && ip.section==MOrigN(tv)){
    MChoiceCell *c=[tv dequeueReusableCellWithIdentifier:@"meine.cell"];
    if(!c) c=[[MChoiceCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"meine.cell"];
    BOOL isTheme=ip.row==0;
    NSString *which=isTheme?@"theme":@"ring";
    NSString *sel=MSelected(which);
    c.titleL.text=[NSString stringWithFormat:@"%@: %@", isTheme?@"Theme máy ảnh":@"Vòng & huy hiệu",
                   sel?MNameOf(which,sel):@"Không dùng"];
    c.iv.image=MThumbFor(which, sel, CGSizeMake(32,32));
    return c;
  }
  return o?o(ds,s,tv,ip):nil;
}
static void hk_select(id ds, SEL s, UITableView *tv, NSIndexPath *ip){
  void (*o)(id,SEL,UITableView*,NSIndexPath*)=(void*)MOrigGet(object_getClass(ds),s);
  if(MIsMyTable(tv) && ip.section==MOrigN(tv)){
    MPresentPicker(MVCFor(tv), ip.row==0?@"theme":@"ring");
    [tv deselectRowAtIndexPath:ip animated:YES];
    return;
  }
  if(o) o(ds,s,tv,ip);
}
static CGFloat hk_height(id ds, SEL s, UITableView *tv, NSIndexPath *ip){
  CGFloat (*o)(id,SEL,UITableView*,NSIndexPath*)=(void*)MOrigGet(object_getClass(ds),s);
  if(MIsMyTable(tv) && ip.section==MOrigN(tv)) return 56;
  return o?o(ds,s,tv,ip):-1;
}

static void MHookDSClass(Class c){
  if(!c) return;
  static char guard; (void)guard;
  NSString *n=MKeyC(c);
  if([MOrig()[n] count]){ /* vẫn lắp tiếp các selector còn thiếu */ }
  MInstall(c,@selector(numberOfSectionsInTableView:),(IMP)hk_numSec,"q@:@");
  MInstall(c,@selector(tableView:numberOfRowsInSection:),(IMP)hk_rows,"q@:@q");
  MInstall(c,@selector(tableView:titleForHeaderInSection:),(IMP)hk_header,"@@:@q");
  MInstall(c,@selector(tableView:cellForRowAtIndexPath:),(IMP)hk_cell,"@@:@@");
  MInstall(c,@selector(tableView:didSelectRowAtIndexPath:),(IMP)hk_select,"v@:@@");
  MInstall(c,@selector(tableView:heightForRowAtIndexPath:),(IMP)hk_height,"d@:@@");
  MLog(@"hooked class %@", n);
}
static void MSetupTable(UITableView *tv){
  if(!tv || objc_getAssociatedObject(tv,kDone)) return;
  objc_setAssociatedObject(tv,kDone,@1,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(tv,kMyTbl,@1,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  MHookDSClass([tv.dataSource class]);
  MHookDSClass([tv.delegate class]);
  MLog(@"settings table ready ds=%@", NSStringFromClass([tv.dataSource class]));
}
static void MScan(UIView *v){
  UITableView *tv=MFindTable(v); if(tv) MSetupTable(tv);
}

// ---------- hook settings sheet ----------
static void (*o_viewDidLoad)(id,SEL);
static void hk_viewDidLoad(id self, SEL s){
  if(o_viewDidLoad) o_viewDidLoad(self,s);
  MScan(((UIViewController*)self).view);
  __weak id wp=self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
    id ss=wp; if(ss) MScan(((UIViewController*)ss).view);
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
    id ss=wp; if(ss) MScan(((UIViewController*)ss).view);
  });
}

__attribute__((constructor)) static void MeineInit(void){
  @autoreleasepool{
    MLog(@"loaded from %@", [MBundle() bundlePath]);
    MLog(@"themes=%lu rings=%lu",(unsigned long)MThemes().count,(unsigned long)MRings().count);
    Class c=NSClassFromString(@"_TtC15SettingsFeature31SettingsMenuSheetViewController");
    if(c){
      Method m=class_getInstanceMethod(c,@selector(viewDidLoad));
      if(m){ o_viewDidLoad=method_getImplementation(m); method_setImplementation(m,(IMP)hk_viewDidLoad);
        MLog(@"swizzled SettingsMenuSheetViewController.viewDidLoad"); }
      else MLog(@"viewDidLoad method MISSING");
    } else MLog(@"SettingsMenuSheetViewController class MISSING");
  }
}