param([string]$Source = "$PSScriptRoot/../assets/app_logo_sources/sinrial-3.2-clean-on-black.png")
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
public static class SinRialBrandAssets {
  static Bitmap Crop(Bitmap image, Rectangle rect) {
    return image.Clone(rect, PixelFormat.Format32bppArgb);
  }
  static Rectangle Bounds(Bitmap image, int left, int right) {
    int x0=right, y0=image.Height, x1=left, y1=0;
    for(int x=left;x<right;x++) for(int y=0;y<image.Height;y++) {
      if(image.GetPixel(x,y).A < 20) continue;
      x0=Math.Min(x0,x); x1=Math.Max(x1,x); y0=Math.Min(y0,y); y1=Math.Max(y1,y);
    }
    return Rectangle.FromLTRB(x0,y0,x1+1,y1+1);
  }
  static void Target(Bitmap image, int size, double fraction, bool background, string path) {
    using(var output=new Bitmap(size,size,PixelFormat.Format32bppArgb))
    using(var g=Graphics.FromImage(output)) {
      g.Clear(background ? Color.Black : Color.Transparent);
      g.InterpolationMode=InterpolationMode.HighQualityBicubic;
      g.PixelOffsetMode=PixelOffsetMode.HighQuality;
      double scale=size*fraction/Math.Max(image.Width,image.Height);
      int w=(int)Math.Round(image.Width*scale), h=(int)Math.Round(image.Height*scale);
      g.DrawImage(image,new Rectangle((size-w)/2,(size-h)/2,w,h));
      output.Save(path,ImageFormat.Png);
    }
  }
  public static void Build(string source,string root) {
    using(var original=new Bitmap(source))
    using(var alpha=new Bitmap(original.Width,original.Height,PixelFormat.Format32bppArgb)) {
      // The approved master is white on black: luminance becomes the alpha mask.
      for(int y=0;y<original.Height;y++) for(int x=0;x<original.Width;x++) {
        Color c=original.GetPixel(x,y);
        int luminance=(c.R*54+c.G*183+c.B*19)/256;
        int a=Math.Max(0,Math.Min(255,(luminance-24)*255/207));
        alpha.SetPixel(x,y,Color.FromArgb(a,255,255,255));
      }
      var bounds=Bounds(alpha,0,alpha.Width);
      int end=bounds.Left, gap=0;
      for(int x=bounds.Left;x<bounds.Right;x++) {
        bool occupied=false;
        for(int y=bounds.Top;y<bounds.Bottom;y++) if(alpha.GetPixel(x,y).A>128) {occupied=true;break;}
        gap=occupied ? 0 : gap+1;
        if(gap>=24) { end=x-gap+1; break; }
      }
      if(end<=bounds.Left) throw new Exception("Cannot locate emblem/text separation");
      using(var full=Crop(alpha,bounds))
      using(var mark=Crop(alpha,Bounds(alpha,bounds.Left,end))) {
        full.Save(root+"/assets/logos/sinrial_full.png",ImageFormat.Png);
        mark.Save(root+"/assets/logos/sinrial_mark.png",ImageFormat.Png);
        Target(mark,1080,.60,false,root+"/android/app/src/main/res/drawable/app_logo.png");
        Target(mark,1080,.60,false,root+"/android/app/src/main/res/drawable/app_logo_monochrome_mask.png");
        string[] folders={"mdpi","hdpi","xhdpi","xxhdpi","xxxhdpi"};
        int[] sizes={48,72,96,144,192};
        for(int i=0;i<folders.Length;i++) Target(mark,sizes[i],.78,true,
          root+"/android/app/src/main/res/mipmap-"+folders[i]+"/ic_launcher.png");
      }
    }
  }
}
'@
$root = [IO.Path]::GetFullPath("$PSScriptRoot/..")
[SinRialBrandAssets]::Build([IO.Path]::GetFullPath($Source), $root)
Write-Output 'Generated full logo, emblem, adaptive foreground, monochrome mask and launcher densities.'
