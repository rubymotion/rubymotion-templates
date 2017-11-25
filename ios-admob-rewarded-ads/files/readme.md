Admob Implementation

The source code is not sufficient to get Admob setup. Read all information
for proper implementation.

This is going to be a very basic explanation of how to integrate AdMob using reward video ads into iOS device running RubyMotion (RM). Reward video ads are ads that when played reward the user with whatever you set as an incentive for watching the video ad (this is my favorite).

Step 1:
Import the Mobile Ads SDK CocoaPods (preferred) using command line
The simplest way to import the SDK into an iOS project is with CocoaPods. Open your project's
Gemfile and add this line to your app's target: gem "motion-cocoapods"

Then from command line run: rake pod:install
Then from the command line if needed run: pod install update or pod install --repo-update

If you're new to CocoaPods , see their official documentation  for info on how to create and use Podfiles.

Step2:
In your project in Rakefile add the following code to your setup function.

this imports the SDK into the build
app.pods do
    pod 'Google-Mobile-Ads-SDK'
end

Step 3:
In your project in the AppDelegate file add the following code to your application function.
To allow videos to be preloaded, we recommend calling loadRequest: as early as possible
(for example, in your app delegate's application:didFinishLaunchingWithOptions: method).
pass your admob account info here, for now we use a test account and have this currently
loading in game_home_scene.
GADRewardBasedVideoAd.sharedInstance().delegate = self
GADRewardBasedVideoAd.sharedInstance().loadRequest(GADRequest.request(), withAdUnitID: 'ca-app-pub-3940256099942544/1712485313')

Step 4:
To allow videos to be preloaded, we recommend calling loadRequest: as early as possible (for example, in your app delegate's didMoveToView method (initializer) which is where I did it in my application.
GADRewardBasedVideoAd.sharedInstance().delegate = self
GADRewardBasedVideoAd.sharedInstance().loadRequest(GADRequest.request(), withAdUnitID: 'ca-app-pub-3940256099942544/1712485313')

Step 5:
Setup all of your callback functions in the same scene which you initilized the loadRequest.

def rewardBasedVideoAd rewardBasedVideoAd, didRewardUserWithReward:reward
    puts "Reward received, giving user their reward here."
  end

def rewardBasedVideoAdDidReceiveAd rewardBasedVideoAd
    puts "Reward based video ad is received."
  end

def rewardBasedVideoAdDidOpen rewardBasedVideoAd
    puts "Opened reward based video ad."
  end

def rewardBasedVideoAdDidStartPlaying rewardBasedVideoAd
    puts "Reward based video ad started playing."
  end

def rewardBasedVideoAdDidClose rewardBasedVideoAd
    puts "Reward based video ad is closed."
  end

def rewardBasedVideoAdWillLeaveApplication rewardBasedVideoAd
    puts "Reward based video ad will leave application."
  end

def rewardBasedVideoAd rewardBasedVideoAd, didFailToLoadWithError:error
    puts "Reward based video ad failed to load."
  end

Step 6:
Setup when you want to call the ad to actually play. For example in this test application when you click/touch on the watch ad button:

def touchesBegan touches, withEvent: _

  identify what was touched, and create a node
  node = nodeAtPoint(touches.allObjects.first.locationInNode(self))

  check if node touched was what you wanted. In this case 'button_ad'
  if (node.name == 'button_ad')
    #check if video has loaded and ready to be viewed, if so lets show it
    if (GADRewardBasedVideoAd.sharedInstance().isReady() == true)
        GADRewardBasedVideoAd.sharedInstance.presentFromRootViewController(root.self)
    end
  end

end

Step 7:
Make sure after the video ad is played successfully or depending when you want to have another ad ready to load that you call to initialize a new ad. This is done by calling the same methods as earlier in the didmoveToView method (initializer) .
GADRewardBasedVideoAd.sharedInstance().delegate = self
GADRewardBasedVideoAd.sharedInstance().loadRequest(GADRequest.request(), withAdUnitID: 'ca-app-pub-3940256099942544/1712485313')

Have fun setting this up!

Pedro V.

# Minimum Requirements #

The minimum requirements to use this template are XCode 9 and
RubyMotion 5.0.

Keep in mind that if you've recently upgraded from a previous versions
of XCode or RubyMotion, you'll want to run `rake clean:all` as opposed
to just `rake clean`.

# Build #

To build using the default simulator, run: `rake` (alias `rake
simulator`).

To run on a specific type of simulator. You can run `rake simulator
device_name="SIMULATOR"`. Here is a list of simulators available:

- `rake simulator device_name='iPhone 5s'
- `rake simulator device_name='iPhone 8 Plus'
- `rake simulator device_name='iPhone 8 Plus'
- `rake simulator device_name='iPhone X'
- `rake simulator device_name='iPad Pro (9.7-inch)'
- `rake simulator device_name='iPad Pro (10.5-inch)'
- `rake simulator device_name='iPad Pro (12.9-inch)'

Consider using https://github.com/KrauseFx/xcode-install (and other
parts of FastLane) to streamline management of simulators,
certificates, and pretty much everything else.

So, for example, you can run `rake simulator device_name='iPhone X'`
to see what your app would look like on iPhone X.

# Deploying to the App Store #

To deploy to the App Store, you'll want to use `rake clean
archive:distribution`. With a valid distribution certificate.

In your `Rakefile`, set the following values:

```ruby
#This is only an example, the location where you store your provisioning profiles is at your discretion.
app.codesign_certificate = "iPhone Distribution: xxxxx" #This is only an example, you certificate name may be different.

#This is only an example, the location where you store your provisioning profiles is at your discretion.
app.provisioning_profile = './profiles/distribution.mobileprovision'
```

For TestFlight builds, you'll need to include the following line
(still using the distribution certificates):

```ruby
app.entitlements['beta-reports-active'] = true
```

# Icons #

As of iOS 11, Apple requires the use of Asset Catalogs for defining
icons and launch screens. You'll find icon and launch screen templates
under `./resources/Assets.xcassets`. You can run the following script
to generate all the icon sizes (once you've specified `1024x1024.png`).
Keep in mind that your `.png` files _cannot_ contain alpha channels.

Save this following script to `./gen-icons.sh` and run it:

```sh
set -x

brew install imagemagick

pushd resources/Assets.xcassets/AppIcon.appiconset/

cp 1024x1024.png "20x20@2x.png"
cp 1024x1024.png "20x20@3x.png"
cp 1024x1024.png "29x29@2x.png"
cp 1024x1024.png "29x29@3x.png"
cp 1024x1024.png "40x40@2x.png"
cp 1024x1024.png "40x40@3x.png"
cp 1024x1024.png "60x60@2x.png"
cp 1024x1024.png "60x60@3x.png"
cp 1024x1024.png "20x20~ipad.png"
cp 1024x1024.png "20x20~ipad@2x.png"
cp 1024x1024.png "29x29~ipad.png"
cp 1024x1024.png "29x29~ipad@2x.png"
cp 1024x1024.png "40x40~ipad.png"
cp 1024x1024.png "40x40~ipad@2x.png"
cp 1024x1024.png "76x76~ipad.png"
cp 1024x1024.png "76x76~ipad@2x.png"
cp 1024x1024.png "83.5x83.5~ipad@2x.png"

mogrify -resize 40x40 "20x20@2x.png"
mogrify -resize 60x60 "20x20@3x.png"
mogrify -resize 58x58 "29x29@2x.png"
mogrify -resize 87x87 "29x29@3x.png"
mogrify -resize 80x80 "40x40@2x.png"
mogrify -resize 120x120 "40x40@3x.png"
mogrify -resize 120x120 "60x60@2x.png"
mogrify -resize 180x180 "60x60@3x.png"
mogrify -resize 20x20 "20x20~ipad.png"
mogrify -resize 40x40 "20x20~ipad@2x.png"
mogrify -resize 29x29 "29x29~ipad.png"
mogrify -resize 58x58 "29x29~ipad@2x.png"
mogrify -resize 40x40 "40x40~ipad.png"
mogrify -resize 80x80 "40x40~ipad@2x.png"
mogrify -resize 76x76 "76x76~ipad.png"
mogrify -resize 152x152 "76x76~ipad@2x.png"
mogrify -resize 167x167 "83.5x83.5~ipad@2x.png"

popd
```

For more information about Asset Catalogs, refer to this link: https://developer.apple.com/library/content/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/
