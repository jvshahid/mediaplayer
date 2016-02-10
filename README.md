### About this project

This is a android library that utilizes ffmpeg for faster decoding. It was
created due to the initial pause in `MediaExtractor` in the standard library
and as a consequence in `MediaPlayer`

#### How to use

##### Download the library


##### Add a project module

`New -> New Module -> Import .JAR/.AAR package`

Set the `Subproject name` to `mediaplayer` and set the File name to the path of
`mediaplayer-release.aar` that you downloaded from the
[Releases page](https://github.com/jvshahid/mediaplayer/releases)


##### Add a the module as a dependency

Update the app's `build.gradle` file to have the following line:

```
dependencies {
    compile project(':mediaplayer')
}
```

Your app `build.gradle` will probably have a `dependencies` block already, in
this case you just add the `compile` line to the end of the block, e.g.:

```
dependencies {
    compile fileTree(dir: 'libs', include: ['*.jar'])
    testCompile 'junit:junit:4.12'
    compile 'com.android.support:appcompat-v7:23.1.1'
    compile 'com.android.support:design:23.1.1'
    compile project(':mediaplayer')
}
```


##### Start the player

Add the following to your code to start the player:

```
import com.github.jvshahid.mediaplayer.AACPlayer;

....


AACPlayer player = new AACPlayer("http://ice33.securenetsystems.net/NILE");
player.play();
```

**Note** do not create a player in an activity. You should start the player in
  a service that runs in the background.


##### API

TODO: document the rest of the api

#### Contributing

TODO: clean up the code and explain the build process

This process assumes a linux environment:

`export SDK=~/Android/Sdk/ && export NDK=$SDK/ndk-bundle && make`

The default make target will do the following:

1. create an arm toolchain
1. build `ffmpeg` for arm
1. build `media-jni` (a light jni layer that utilizes ffmpeg)
1. package everything in a `aar` file

#### Note about LICENSE

This code is licensed under `MIT` but make use of `ffmpeg` which is `LGPL`
licensed. **note** `MediaPlayer` doesn't turn on `GPL` features of `ffmpeg`, so
it should be safe to use this library in commercial products.
