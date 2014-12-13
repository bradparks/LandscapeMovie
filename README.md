An iOS client that runs on iPhone4 (and newer) and iPad 2 and newer devices. This client
will detect the type of iOS device then download a 480p, 720p, or 1080p resolution video
depending on the screen dimensions of the iPhone/iPad. Note that a retina iPad device
provides the best viewing experience since a 1080p resolution video will be displayed.

This client is a demo of how to handle data provided by this google app engine hosted
free CDN service:

https://github.com/mdejong/GoFreeCDN

The client supports up to 4 URL downloads at the same time, note that this is limited by
iOS as described here:

http://blog.lightstreamer.com/2013/01/on-ios-url-connection-parallelism-and.html

You will need to download the iOS Xcode project and install it on your device.
By default, the client will connect to an already setup GAE instance, but
if you want to setup your own GoFreeCDN (either locally or on GAE) then
have a look at the startMovieDownload method in ViewController.m and
change the GAE address for the variable servicePrefix to your own GAE instance.

The already configured GAE instance has a 1 gig daily limit and I have not
enabled billing, so it will likely work but might not if too many people have
tried this example in a 24 hour period.

