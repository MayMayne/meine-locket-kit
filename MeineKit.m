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

static NSHashTable *MPics(void);
static void MPresentPicker(UIViewController *from, NSString *which);
// ---------- trang Profile (theo mockup: ảnh bìa blur + avatar lệch phải + 2 card) ----------
// ảnh avatar đang hiện trên màn hình (lớn nhất trong các pic đã thấy)
static UIImage *MAvatarPic(void){
  UIImage *best=nil; CGFloat a=0;
  for(UIView *pic in [MPics() allObjects]){
    CGFloat ar=pic.bounds.size.width*pic.bounds.size.height;
    if(ar<=0) continue;
    UIImage *im=nil;
    if([pic isKindOfClass:UIImageView.class]) im=((UIImageView*)pic).image;
    if(!im) for(UIView *v in pic.subviews)
      if([v isKindOfClass:UIImageView.class] && ((UIImageView*)v).image){ im=((UIImageView*)v).image; break; }
    if(im && ar>a){ a=ar; best=im; }
  }
  return best;
}
//  ảnh bìa lấy từ thư viện (lưu vào Documents, blur theo style mockup)
static NSString *MCoverPath(void){
  NSString *d=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
  return [d stringByAppendingPathComponent:@"meine_cover.jpg"];
}
static UIImage *MCoverLoad(void){
  return [[NSFileManager defaultManager] fileExistsAtPath:MCoverPath()]
    ?[UIImage imageWithContentsOfFile:MCoverPath()]:nil;
}
static UIImage *MNorm(UIImage *im){
  if(!im) return nil;
  if(im.imageOrientation==UIImageOrientationUp && MAX(im.size.width,im.size.height)<=2048) return im;
  CGFloat m=MAX(im.size.width,im.size.height), k=1.0;
  if(m>2048) k=2048.0/m;
  CGSize sz=CGSizeMake(im.size.width*k, im.size.height*k);
  UIGraphicsBeginImageContextWithOptions(sz,NO,im.scale);
  [im drawInRect:CGRectMake(0,0,sz.width,sz.height)];
  UIImage *o=UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return o?:im;
}
static BOOL MCoverSave(UIImage *im){
  NSData *d=UIImageJPEGRepresentation(MNorm(im),0.9);
  return d?[d writeToFile:MCoverPath() atomically:YES]:NO;
}

// ---------- "Cá nhân hoá" chèn vào TRANG PROFILE THẬT ----------
// KHÔNG đụng dataSource/delegate (không bao giờ trap index): toàn bộ nội dung nằm trong
// tableHeaderView = [ảnh bìa từ thư viện] + [header profile gốc của app] + [khối MOD].

static const void *kWrap = &kWrap;
static const void *kVan  = &kVan;
static const void *kBlk2 = &kBlk2;

@interface MPBlock : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic, weak) UIImageView *coverView;
@end
@implementation MPBlock
- (void)tapCover{
  UIViewController *h = self.host; if(!h) return;
  if(![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
  UIImagePickerController *pk = [[UIImagePickerController alloc] init];
  pk.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
  pk.delegate = self;
  [h presentViewController:pk animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)p didFinishPickingMediaWithInfo:(NSDictionary *)info{
  UIImage *im = info[UIImagePickerControllerOriginalImage];
  if(im && MCoverSave(im) && self.coverView) self.coverView.image = MBlur(im, 28);
  [p dismissViewControllerAnimated:YES completion:nil];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)p{ [p dismissViewControllerAnimated:YES completion:nil]; }
- (void)tapTheme{ MPresentPicker(self.host, @"theme"); }
- (void)tapRing{ MPresentPicker(self.host, @"ring"); }
- (void)tapTG{
  NSURL *u = [NSURL URLWithString:@"https://t.me/erorr404909"];
  if(u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
}
@end

static const CGFloat kPad = 16;

static CGFloat MAddCard(UIView *b, CGFloat y, CGFloat w, NSString *title, NSString *which, id target, SEL act){
  CGFloat h = 158;
  UIView *card = [[UIView alloc] initWithFrame:CGRectMake(kPad, y, w-2*kPad, h)];
  card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  card.backgroundColor = [UIColor secondarySystemBackgroundColor];
  card.layer.cornerRadius = 16;
  card.userInteractionEnabled = YES;
  [card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:act]];
  [b addSubview:card];
  UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(14, 12, card.bounds.size.width-124, 24)];
  t.font = [UIFont boldSystemFontOfSize:16]; t.text = title;
  [card addSubview:t];
  UILabel *more = [[UILabel alloc] initWithFrame:CGRectMake(card.bounds.size.width-110, 14, 96, 20)];
  more.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
  more.font = [UIFont systemFontOfSize:13];
  more.textColor = [UIColor systemBlueColor];
  more.text = @"Xem tất cả ›";
  more.textAlignment = NSTextAlignmentRight;
  [card addSubview:more];
  UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 44, card.bounds.size.width-20, 104)];
  sv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  sv.showsHorizontalScrollIndicator = NO;
  [card addSubview:sv];
  NSString *sel = MSelected(which);
  NSArray *ids = [which isEqualToString:@"ring"] ? MRings() : MThemes();
  CGFloat x = 4;
  for(NSDictionary *it in ids){
    if(x > 380) break;
    NSString *iid = it[@"id"];
    UIView *cell = [[UIView alloc] initWithFrame:CGRectMake(x, 0, 56, 98)];
    UIImageView *imv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    imv.contentMode = UIViewContentModeScaleAspectFill;
    imv.clipsToBounds = YES;
    imv.layer.cornerRadius = 12;
    imv.image = MThumbFor(which, iid, CGSizeMake(56, 56));
    if(sel && [sel isEqualToString:iid]){
      imv.layer.borderWidth = 2.5;
      imv.layer.borderColor = [UIColor systemBlueColor].CGColor;
    }
    [cell addSubview:imv];
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(-3, 58, 62, 38)];
    lb.font = [UIFont systemFontOfSize:9];
    lb.numberOfLines = 2;
    lb.textAlignment = NSTextAlignmentCenter;
    lb.textColor = [UIColor secondaryLabelColor];
    lb.text = it[@"name"];
    [cell addSubview:lb];
    [sv addSubview:cell];
    x += 60;
  }
  sv.contentSize = CGSizeMake(x+4, 104);
  return h;
}

static CGFloat MAddMeine(UIView *b, CGFloat y, CGFloat w, id target, SEL act){
  CGFloat h = 84;
  UIView *row = [[UIView alloc] initWithFrame:CGRectMake(kPad, y, w-2*kPad, h)];
  row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  row.userInteractionEnabled = YES;
  [row addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:act]];
  [b addSubview:row];
  UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectMake((row.bounds.size.width-150)/2, 8, 150, 44)];
  logo.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
  logo.contentMode = UIViewContentModeScaleAspectFit;
  logo.image = MImg(@"logo/meine-logo.png");
  [row addSubview:logo];
  UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(0, 56, row.bounds.size.width, 20)];
  lb.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  lb.textAlignment = NSTextAlignmentCenter;
  lb.font = [UIFont systemFontOfSize:13];
  lb.textColor = [UIColor systemBlueColor];
  lb.text = @"by Mây";
  [row addSubview:lb];
  return h;
}

static CGFloat MProfileBlockBody(UIView *b, CGFloat w, MPBlock *tb){
  CGFloat y = 12;
  UILabel *h1 = [[UILabel alloc] initWithFrame:CGRectMake(kPad, y, w-2*kPad, 26)];
  h1.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  h1.font = [UIFont boldSystemFontOfSize:19];
  h1.text = @"Cá nhân hoá";
  [b addSubview:h1];
  UILabel *mod = [[UILabel alloc] init];
  mod.text = @" MOD ";
  mod.font = [UIFont boldSystemFontOfSize:10];
  mod.textColor = [UIColor blackColor];
  mod.backgroundColor = [UIColor systemYellowColor];
  mod.layer.cornerRadius = 7;
  mod.clipsToBounds = YES;
  mod.textAlignment = NSTextAlignmentCenter;
  [mod sizeToFit];
  mod.frame = CGRectMake(w-kPad-mod.frame.size.width-6, y+4, mod.frame.size.width+6, 18);
  mod.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
  [b addSubview:mod];
  y += 28;
  UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(kPad, y, w-2*kPad, 18)];
  sub.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  sub.font = [UIFont systemFontOfSize:13];
  sub.textColor = [UIColor secondaryLabelColor];
  sub.text = @"Chỉ hiển thị trên máy của bạn";
  [b addSubview:sub];
  y += 26;
  y += MAddCard(b, y, w, @"Theme", @"theme", tb, @selector(tapTheme)) + 8;
  y += MAddCard(b, y, w, @"Vòng & huy hiệu", @"ring", tb, @selector(tapRing)) + 4;
  y += MAddMeine(b, y, w, tb, @selector(tapTG)) + 8;
  b.frame = CGRectMake(0, 0, w, y);
  return y;
}

static UIView *MProfileBlock(CGFloat w, MPBlock *tb){
  UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 480)];
  b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  b.backgroundColor = [UIColor clearColor];
  MProfileBlockBody(b, w, tb);
  return b;
}

static void MLogHierarchy(UITableView *tv){
  @try{
    UIView *h = tv.tableHeaderView;
    NSMutableString *s = [NSMutableString stringWithFormat:@"HIER hdr=%@", h?NSStringFromClass(h.class):@"nil"];
    if(h){
      for(UIView *v in h.subviews){
        NSString *tx = MViewText(v);
        if(tx.length > 60) tx = [tx substringToIndex:60];
        [s appendFormat:@" >%@[%@]", NSStringFromClass(v.class), tx];
      }
    }
    MLog(@"%@", s);
    id ds = tv.dataSource;
    NSInteger ns = 1, r0 = 0;
    if([ds respondsToSelector:@selector(numberOfSectionsInTableView:)])
      ns = ((NSInteger(*)(id,SEL,UITableView*))objc_msgSend)(ds, @selector(numberOfSectionsInTableView:), tv);
    if([ds respondsToSelector:@selector(tableView:numberOfRowsInSection:)])
      r0 = ((NSInteger(*)(id,SEL,UITableView*,NSInteger))objc_msgSend)(ds, @selector(tableView:numberOfRowsInSection:), tv, 0);
    NSString *c0 = @"";
    if(r0 > 0 && [ds respondsToSelector:@selector(tableView:cellForRowAtIndexPath:)]){
      id cell = ((id(*)(id,SEL,UITableView*,NSIndexPath*))objc_msgSend)(ds, @selector(tableView:cellForRowAtIndexPath:), tv,
                                                                          [NSIndexPath indexPathForRow:0 inSection:0]);
      c0 = MViewText(cell);
      if(c0.length > 60) c0 = [c0 substringToIndex:60];
    }
    MLog(@"HIER sections=%ld sec0rows=%ld cell0=%@", (long)ns, (long)r0, c0);
  }@catch(NSException *e){ MLog(@"HIER err %@", e); }
}

static void MInstallProfile(UIViewController *vc){
  if(!vc) return;
  UITableView *tv = MFindTable(vc.view);
  if(!tv){ MLog(@"profile: table not found"); return; }
  CGFloat w = tv.bounds.size.width;
  if(w < 50){ MLog(@"profile: width %d — skip", (int)w); return; }
  UIView *cur = tv.tableHeaderView;
  BOOL ours = (cur && objc_getAssociatedObject(cur, kWrap));
  if(ours && fabs(cur.frame.size.width - w) < 1.5 && cur.frame.size.height > 300){
    MLog(@"profile block ok (w=%d h=%d)", (int)w, (int)cur.frame.size.height);
    return;
  }
  UIView *van = ours ? (UIView*)objc_getAssociatedObject(cur, kVan) : cur;
  if(ours) [cur removeFromSuperview];
  MPBlock *tb = objc_getAssociatedObject(tv, kBlk2);
  if(!tb){
    tb = [MPBlock new];
    objc_setAssociatedObject(tv, kBlk2, tb, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  tb.host = vc;
  // ảnh bìa từ thư viện (blur nhẹ) — chạm để chọn
  UIImageView *cover = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, w, 180)];
  cover.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  cover.contentMode = UIViewContentModeScaleAspectFill;
  cover.clipsToBounds = YES;
  UIImage *cv = MCoverLoad();
  if(!cv) cv = MAvatarPic();
  cover.image = cv ? MBlur(cv, 28) : nil;
  if(!cover.image) cover.backgroundColor = [UIColor systemGray5Color];
  cover.userInteractionEnabled = YES;
  [cover addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:tb action:@selector(tapCover)]];
  tb.coverView = cover;
  UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(12, 180-30, w-24, 22)];
  hint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
  hint.text = @"  Chạm để chọn ảnh bìa từ thư viện";
  hint.font = [UIFont systemFontOfSize:12];
  hint.textColor = [UIColor whiteColor];
  hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
  hint.layer.cornerRadius = 11;
  hint.clipsToBounds = YES;
  [cover addSubview:hint];
  UIView *blk = MProfileBlock(w, tb);
  CGFloat vanH = van ? van.frame.size.height : 0;
  CGFloat blkH = blk.frame.size.height;
  UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 180+vanH+blkH)];
  wrap.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  objc_setAssociatedObject(wrap, kWrap, @1, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(wrap, kVan, van, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [wrap addSubview:cover];
  if(van){
    van.frame = CGRectMake(0, 180, w, vanH);
    van.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [wrap addSubview:van];
  }
  blk.frame = CGRectMake(0, 180+vanH, w, blkH);
  [wrap addSubview:blk];
  tv.tableHeaderView = wrap;
  MLog(@"profile block installed w=%d vanH=%d blkH=%d van=%@",
       (int)w, (int)vanH, (int)blkH, van?NSStringFromClass(van.class):@"none");
  MLogHierarchy(tv);
}

// ---------- quét trang profile (không cần biết tên class) ----------
static UIViewController *MTopVC(void){
  for(UIWindow *w in [UIApplication sharedApplication].windows){
    if(!w.isKeyWindow) continue;
    UIViewController *vc=w.rootViewController;
    while(vc){
      if(vc.presentedViewController) vc=vc.presentedViewController;
      else if([vc isKindOfClass:UINavigationController.class])
        vc=((UINavigationController*)vc).visibleViewController;
      else if([vc isKindOfClass:UITabBarController.class])
        vc=((UITabBarController*)vc).selectedViewController;
      else break;
    }
    if(vc) return vc;
  }
  return nil;
}
static BOOL MIsProfileVC(UIViewController *vc){
  if(!vc) return NO;
  NSString *cn=NSStringFromClass(vc.class).lowercaseString;
  if([cn containsString:@"camera"]||[cn containsString:@"settings"]||[cn containsString:@"picker"]) return NO;
  if([cn containsString:@"profile"]) return YES;
  // có mặt avatar ProfilePictureView trong hierarchy → trang profile
  __block BOOL found=NO;
  void (^walk)(UIView*,NSInteger)=^(UIView *v,NSInteger d){
    if(found||!v||d>4) return;
    if([NSStringFromClass(v.class) containsString:@"ProfilePicture"]){ found=YES; return; }
    for(UIView *c in v.subviews) walk(c,d+1);
  };
  walk(vc.view,0);
  return found;
}
static NSString *gTopName;
static void MTimerTick(void){
  UIViewController *vc=MTopVC();
  NSString *n=vc?NSStringFromClass(vc.class):@"none";
  if(!gTopName || ![gTopName isEqualToString:n]){
    gTopName=n;
    MLog(@"topVC changed → %@", n);
    if(vc) MLogHierarchy(MFindTable(vc.view));
  }
  if(MIsProfileVC(vc)) MInstallProfile(vc);
}
static void MStartScanner(void){
  dispatch_async(dispatch_get_main_queue(),^{
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t){ MTimerTick(); }];
    MLog(@"profile scanner started");
  });
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
  // ĐẶT SAU ẢNH CAMERA, TRƯỚC các nút của Locket (không được đè lên UI)
  static BOOL logged;
  if(!logged){
    logged=YES;
    NSMutableString *hs=[NSMutableString stringWithFormat:@"cam[%@] subviews:",NSStringFromClass(object_getClass(v))];
    for(UIView *c in v.subviews) [hs appendFormat:@" %@(%0.fx%0.f)",NSStringFromClass(c.class),c.frame.size.width,c.frame.size.height];
    MLog(@"%@",hs);
  }
  UIView *feed=nil;
  for(UIView *c in v.subviews){
    if(c==ov) continue;
    if(c.frame.size.width>=v.bounds.size.width*0.9 && c.frame.size.height>=v.bounds.size.height*0.9){ feed=c; break; }
  }
  if(feed && ov.superview==v) [v insertSubview:ov aboveSubview:feed];
  else if(ov.superview==v) [v sendSubviewToBack:ov];
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
  UIView *sp=pic.superview;
  NSDictionary *it=MItem(@"ring", MSelected(@"ring")?:@"");
  UIView *ov=objc_getAssociatedObject(pic,kAssocOv);
  if(!sp || !it){
    [ov removeFromSuperview];
    objc_setAssociatedObject(pic,kAssocOv,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return;
  }
  CGRect r=pic.frame;   // frame relative to superview — bám theo avatar mọi lúc (kể cả khi scroll)
  if(r.size.width<4||r.size.height<4) return;
  CGRect big=CGRectMake(r.origin.x-r.size.width*0.10, r.origin.y-r.size.height*0.10,
                        r.size.width*1.20, r.size.height*1.20);
  if(!ov || ov.superview!=sp){
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
    // ĐẶT LÀ EM CÙNG CHA CỦA AVATAR, ngay phía trên nó → z-order/position luôn đúng,
    // theo scroll tự nhiên, không hiện ở màn hình khác
    [sp insertSubview:ov aboveSubview:pic];
    objc_setAssociatedObject(pic,kAssocOv,ov,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MLog(@"ring overlay created (sibling) cls=%@",NSStringFromClass(object_getClass(pic)));
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
}
static __thread BOOL gPicBusy;   // chống gọi lặp: hook khác (LocketFull6...) lookup lại IMP tại chỗ
static void hk_picLayout(id self, SEL s){
  static int gPicN; gPicN++;
    if(gPicN<=6 || (gPicN<=60 && gPicN%10==0) || gPicN%500==0)
      MLog(@"pic enter#%d cls=%@",gPicN,NSStringFromClass(object_getClass(self)));
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
  MLog(@"viewDidLoad vc=%@", NSStringFromClass(object_getClass(self)));
  if(o_viewDidLoad) o_viewDidLoad(self,s);
  __weak id wp=self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
    id ss=wp; if(ss) MInstallProfile((UIViewController*)ss);
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
    id ss=wp; if(ss) MInstallProfile((UIViewController*)ss);
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
    MStartScanner();
    MLog(@"=== MeineKit ready ===");
  }
} 