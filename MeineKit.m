// MeineKit.m — Meine customizer (theme máy ảnh / vòng+huy hiệu / ảnh bìa profile)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreImage/CoreImage.h>
#include <stdio.h>
#include <time.h>

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
// log FILE luôn bật (cho chẩn đoán crash) — ghi Documents/meine.log, flush mỗi dòng
static FILE *MFP(void){
  static FILE *f; static dispatch_once_t o;
  dispatch_once(&o,^{
    NSString *d=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *p=[d stringByAppendingPathComponent:@"meine.log"];
    f=fopen(p.fileSystemRepresentation,"a");
    if(!f) f=fopen("/tmp/meine.log","a");
    if(f) setvbuf(f,NULL,_IONBF,0);
  });
  return f;
}
static void MFileLog(NSString *s){
  FILE *f=MFP(); if(!f) return;
  char ts[16]; time_t t=time(NULL); struct tm tm={0};
  localtime_r(&t,&tm); strftime(ts,sizeof ts,"%H:%M:%S",&tm);
  fprintf(f,"[%s] %s\n",ts,s.UTF8String);
  fflush(f);
}
#define MLog(fmt,...) do{ NSString *_ms=[NSString stringWithFormat:@"[Meine] " fmt, ##__VA_ARGS__]; \
  MFileLog(_ms); if(MLogOn()) NSLog(@"%@",_ms); }while(0)

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
static UIImage *MImg(NSString *rel){
  if(!rel.length) return nil;
  static NSCache *cc; static dispatch_once_t o;
  dispatch_once(&o,^{ cc=[NSCache new]; cc.countLimit=48; });
  UIImage *im=[cc objectForKey:rel];
  if(!im){ NSString *p=MPath(rel); if(!p) return nil;
    im=[UIImage imageWithContentsOfFile:p];
    if(im) [cc setObject:im forKey:rel]; }
  return im;
}

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
  self.backgroundColor=[UIColor clearColor];
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
  self.cv.backgroundColor=[UIColor clearColor];
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
  if(!m){
    // chỉ thêm method mới khi vắng mặt là vô hại với table khác:
    // numberOfSections mặc định system = 1, titleForHeader mặc định = nil
    BOOL addable=(s==@selector(numberOfSectionsInTableView:) ||
                  s==@selector(tableView:titleForHeaderInSection:));
    if(!addable){ MLog(@"skip missing %s on %@", sel_getName(s), MKeyC(c)); return NO; }
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
// Số section THẬT (lưu lại khi UIKit hỏi); KHÔNG bịa section giả —
// mọi API không hook (footer/canEdit/...) đều phải nhận index thật
static NSInteger hk_numSec(id ds, SEL s, UITableView *tv){
  NSInteger (*o)(id,SEL,UITableView*)=(void*)MOrigGet(object_getClass(ds),s);
  NSInteger n=o?o(ds,s,tv):1;
  if(MIsMyTable(tv))
    objc_setAssociatedObject(tv,kOrigN,@(n),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return n;
}
// Trả base (index row đầu của ta) trong section CUỐI thật, hoặc NSNotFound.
// Chỉ dùng index có thật → không thể gây trap phía code gốc.
static NSInteger MMyBase(id ds, UITableView *tv, NSIndexPath *ip){
  if(!MIsMyTable(tv)) return NSNotFound;
  NSInteger last=MOrigN(tv)-1;
  if(last<0 || ip.section!=last) return NSNotFound;
  SEL r=@selector(tableView:numberOfRowsInSection:);
  NSInteger (*o)(id,SEL,UITableView*,NSInteger)=(void*)MOrigGet(object_getClass(ds),r);
  if(!o) return NSNotFound;
  NSInteger base=o(ds,r,tv,last);
  return (ip.row>=base && ip.row<base+2)?base:NSNotFound;
}
static NSInteger hk_rows(id ds, SEL s, UITableView *tv, NSInteger sec){
  NSInteger (*o)(id,SEL,UITableView*,NSInteger)=(void*)MOrigGet(object_getClass(ds),s);
  NSInteger n=o?o(ds,s,tv,sec):0;
  if(MIsMyTable(tv) && o && MOrigN(tv)>0 && sec==MOrigN(tv)-1) n+=2; // ghi nối 2 row vào section cuối
  return n;
}
static id hk_header(id ds, SEL s, UITableView *tv, NSInteger sec){
  id (*o)(id,SEL,UITableView*,NSInteger)=(void*)MOrigGet(object_getClass(ds),s);
  return o?o(ds,s,tv,sec):nil;   // giữ header gốc của app
}
static id hk_cell(id ds, SEL s, UITableView *tv, NSIndexPath *ip){
  id (*o)(id,SEL,UITableView*,NSIndexPath*)=(void*)MOrigGet(object_getClass(ds),s);
  NSInteger base=MMyBase(ds,tv,ip);
  if(base!=NSNotFound){
    MChoiceCell *c=[tv dequeueReusableCellWithIdentifier:@"meine.cell"];
    if(!c) c=[[MChoiceCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"meine.cell"];
    BOOL isTheme=(ip.row==base);
    NSString *which=isTheme?@"theme":@"ring";
    NSString *sel=MSelected(which);
    c.titleL.text=[NSString stringWithFormat:@"%@: %@", isTheme?@"Theme máy ảnh":@"Vòng & huy hiệu",
                   sel?MNameOf(which,sel):@"Không dùng"];
    c.iv.image=MThumbFor(which, sel, CGSizeMake(32,32));
    return c;
  }
  if(o) return o(ds,s,tv,ip);
  // không bao giờ trả nil cell (UITableView exception)
  return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}
static void hk_select(id ds, SEL s, UITableView *tv, NSIndexPath *ip){
  void (*o)(id,SEL,UITableView*,NSIndexPath*)=(void*)MOrigGet(object_getClass(ds),s);
  NSInteger base=MMyBase(ds,tv,ip);
  if(base!=NSNotFound){
    MPresentPicker(MVCFor(tv), ip.row==base?@"theme":@"ring");
    [tv deselectRowAtIndexPath:ip animated:YES];
    return;
  }
  if(o) o(ds,s,tv,ip);
}
static CGFloat hk_height(id ds, SEL s, UITableView *tv, NSIndexPath *ip){
  CGFloat (*o)(id,SEL,UITableView*,NSIndexPath*)=(void*)MOrigGet(object_getClass(ds),s);
  if(MMyBase(ds,tv,ip)!=NSNotFound) return 56;
  if(o) return o(ds,s,tv,ip);
  // không bao giờ ép -1/automatic khi delegate gốc không implement
  if(tv && tv.rowHeight>0) return tv.rowHeight;
  return 44;
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
  // CHỈ đụng table của đúng SettingsMenuSheetViewController — table profile/menu khác bỏ qua
  Class sheet=NSClassFromString(@"_TtC15SettingsFeature31SettingsMenuSheetViewController");
  UIViewController *vc=MVCFor(tv);
  if(sheet && ![vc isKindOfClass:sheet]){
    MLog(@"skip foreign table vc=%@", NSStringFromClass([vc class]));
    return;
  }
  objc_setAssociatedObject(tv,kDone,@1,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(tv,kMyTbl,@1,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  MHookDSClass([tv.dataSource class]);
  MHookDSClass([tv.delegate class]);
  MLog(@"settings table ready ds=%@", NSStringFromClass([tv.dataSource class]));
}
static void MScan(UIView *v){
  UITableView *tv=MFindTable(v); if(tv) MSetupTable(tv);
}

// ---------- theme lên camera preview ----------
static void MOverlayUpdate(NSString *sel){
  for(UIWindow *w in [UIApplication sharedApplication].windows){
    UIView *ov=[w viewWithTag:kTagCam];
    if(!ov) continue;
    if(!sel.length){ [ov removeFromSuperview]; continue; }
    if(![ov isKindOfClass:UIImageView.class]) continue;
    ((UIImageView*)ov).image=MImg([NSString stringWithFormat:@"themes/%@/frame.png",sel]);
  }
}
static void hk_camLayout(id self, SEL s){
  IMP o=MOrigGet(object_getClass(self),s);
  if(o) ((void(*)(id,SEL))o)(self,s);
  @try{
  UIView *v=((UIViewController*)self).view; if(!v) return;
  NSString *sel=MSelected(@"theme");
  UIView *ov=[v viewWithTag:kTagCam];
  if(!sel.length){ [ov removeFromSuperview]; return; }
  if(!ov || ![ov isKindOfClass:UIImageView.class]){
    ov=[[UIImageView alloc] init];
    ov.tag=kTagCam;
    ((UIImageView*)ov).contentMode=UIViewContentModeScaleAspectFill;
    ov.clipsToBounds=YES; ov.userInteractionEnabled=NO;
    [v addSubview:ov];
    MLog(@"camera overlay created on %@", NSStringFromClass(object_getClass(self)));
  }
  ov.frame=v.bounds;
  ((UIImageView*)ov).image=MImg([NSString stringWithFormat:@"themes/%@/frame.png",sel]);
  [v bringSubviewToFront:ov];
  }@catch(NSException *e){ MLog(@"cam exception: %@",e); }
}
static void hk_picLayout(id self, SEL s);
static NSHashTable *MPics(void);
static void MInstallCamHooks(void){
  const char *ty="v@:";
  for(NSString *cn in @[@"_TtC6Camera20CameraViewController",@"LFCameraViewController"]){
    Class c=NSClassFromString(cn);
    if(!c){ MLog(@"cam class missing: %@",cn); continue; }
    if(MInstall(c,@selector(viewDidLayoutSubviews),(IMP)hk_camLayout,ty))
      MLog(@"cam layout hooked: %@",cn);
    else MLog(@"cam layout already/fail: %@",cn);
  }
  // hook theo thứ tự: class con trước (nếu có), tránh MOrigGet walk dừng nhầm
  for(NSString *cn in @[@"_TtC14ProfilePicture28ProfilePictureViewSelfSizing",
                        @"_TtC14ProfilePicture35UnifiedProfilePictureViewSelfSizing",
                        @"_TtC14ProfilePicture18ProfilePictureView"]){
    Class pp=NSClassFromString(cn);
    if(pp && MInstall(pp,@selector(layoutSubviews),(IMP)hk_picLayout,ty))
      MLog(@"profile picture hooked: %@",cn);
    else MLog(@"profile picture NOT hooked: %@",cn);
  }
  [[NSNotificationCenter defaultCenter] addObserverForName:MKey(@"theme") object:nil
    queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){
      MOverlayUpdate(MSelected(@"theme"));
    }];
  [[NSNotificationCenter defaultCenter] addObserverForName:MKey(@"ring") object:nil
    queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){
      for(UIView *pic in MPics()){ [pic setNeedsLayout]; }
    }];
}

// ---------- vòng + huy hiệu lên avatar (ProfilePictureView) ----------
static const void *kAssocOv=&kAssocOv;
static NSHashTable *MPics(void){ static NSHashTable *t; static dispatch_once_t o;
  dispatch_once(&o,^{ t=[NSHashTable weakObjectsHashTable]; }); return t; }
// KHÔNG thêm subview vào chính ProfilePictureView: code gốc của app iterate/force-cast
// subviews trong layoutSubviews → chèn UIView lạ vào là Swift trap. Đặt overlay ở window.
static void MRingApply(UIView *pic){
  if(![pic isKindOfClass:UIView.class]) return;
  [MPics() addObject:pic];
  UIWindow *win=pic.window;
  UIView *ov=objc_getAssociatedObject(pic,kAssocOv);
  NSDictionary *it=MItem(@"ring", MSelected(@"ring")?:@"");
  if(!win || !it){
    [ov removeFromSuperview];
    objc_setAssociatedObject(pic,kAssocOv,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return;
  }
  CGRect r=[pic convertRect:pic.bounds toView:win];
  if(r.size.width<4||r.size.height<4) return;
  CGRect big=CGRectMake(r.origin.x-r.size.width*0.10, r.origin.y-r.size.height*0.10,
                        r.size.width*1.20, r.size.height*1.20);
  if(!ov || ov.superview!=win){
    if(ov) [ov removeFromSuperview];
    ov=[[UIView alloc] initWithFrame:big];
    ov.userInteractionEnabled=NO; ov.backgroundColor=[UIColor clearColor]; ov.clipsToBounds=NO;
    UIImageView *rv=[[UIImageView alloc] initWithFrame:ov.bounds];
    rv.tag=kTagRingImg; rv.contentMode=UIViewContentModeScaleAspectFit;
    rv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [ov addSubview:rv];
    UIImageView *bv=[[UIImageView alloc] init];
    bv.tag=kTagBadgeImg; bv.contentMode=UIViewContentModeScaleAspectFit;
    [ov addSubview:bv];
    [win addSubview:ov];
    objc_setAssociatedObject(pic,kAssocOv,ov,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MLog(@"ring overlay created (window-level)");
  }
  ov.frame=big;
  ((UIImageView*)[ov viewWithTag:kTagRingImg]).image=MImg(it[@"ring"]);
  UIImageView *bv=(UIImageView*)[ov viewWithTag:kTagBadgeImg];
  bv.image=MImg(it[@"badge"]);
  CGFloat bw=big.size.width*0.34;
  CGFloat R=big.size.width*0.45;
  CGFloat cx=big.size.width*0.5 + R*sin(50.0*M_PI/180.0);
  CGFloat cy=big.size.height*0.5 - R*cos(50.0*M_PI/180.0);
  bv.frame=CGRectMake(cx-bw*0.5, cy-bw*0.5, bw, bw);
  // z-order: ngay phía trên nhánh của pic trong window (không trồi lên modal phía sau)
  UIView *top=pic;
  while(top.superview && top.superview!=win) top=top.superview;
  if(top.superview==win && top!=ov)
    [win insertSubview:ov aboveSubview:top];
}
static __thread BOOL gPicBusy;   // chống gọi lặp: hook khác (LocketFull6...) lookup lại IMP tại chỗ
static void hk_picLayout(id self, SEL s){
  static int gPicN; if(gPicN<50){ gPicN++;
    if(gPicN<=6 || gPicN%10==0)
      MLog(@"pic enter#%d cls=%@",gPicN,NSStringFromClass(object_getClass(self))); }
  IMP o=MOrigGet(object_getClass(self),s);
  if(!o){
    MLog(@"pic ORIG-MISSING cls=%@",NSStringFromClass(object_getClass(self)));
  }else if(o==(IMP)hk_picLayout){
    MLog(@"pic RECURSION-detected cls=%@",NSStringFromClass(object_getClass(self)));
  }else if(gPicBusy){
    MLog(@"pic NESTED-skip cls=%@",NSStringFromClass(object_getClass(self)));
  }else{
    gPicBusy=YES;
    @try{ ((void(*)(id,SEL))o)(self,s); }
    @finally{ gPicBusy=NO; }
  }
  @try{ MRingApply((UIView*)self); }
  @catch(NSException *e){ MLog(@"ring exception: %@",e); }
}

// ---------- hook settings sheet ----------
static void (*o_viewDidLoad)(id,SEL);
static void hk_viewDidLoad(id self, SEL s){
  MLog(@"settings viewDidLoad vc=%@", NSStringFromClass(object_getClass(self)));
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
    MLog(@"=== MeineKit start (diag build) ===");
    MLog(@"loaded from %@", [MBundle() bundlePath]);
    MLog(@"themes=%lu rings=%lu",(unsigned long)MThemes().count,(unsigned long)MRings().count);
    MInstallCamHooks();
    Class c=NSClassFromString(@"_TtC15SettingsFeature31SettingsMenuSheetViewController");
    if(c){
      SEL vl=@selector(viewDidLoad);
      Method m=class_getInstanceMethod(c,vl);
      if(m){
        IMP orig=method_getImplementation(m);
        const char *ty=method_getTypeEncoding(m)?: "v@:";
        // phạm vi an toàn: KHÔNG sửa Method dùng chung của superclass
        if(class_addMethod(c,vl,(IMP)hk_viewDidLoad,ty)){
          o_viewDidLoad=(void(*)(id,SEL))orig;
        }else{
          Method own=class_getInstanceMethod(c,vl);
          o_viewDidLoad=(void(*)(id,SEL))method_setImplementation(own,(IMP)hk_viewDidLoad);
        }
        MLog(@"swizzled SettingsMenuSheetViewController.viewDidLoad (scoped)");
      }
      else MLog(@"viewDidLoad method MISSING");
    } else MLog(@"SettingsMenuSheetViewController class MISSING");
    MLog(@"=== MeineKit ready ===");
  }
}