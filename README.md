# SuperMediaSlideShow
SuperMediaSlideSHow, OBS-Studio lua Automated Media Presentation System focused on Images and Videos and a enough Workflow to make a whole movie.

SMSS is a lua script that drives the OBS-Studio Image and or Media source to deliver a well featured Multi-Media Slide Show like presentation. Media files are loaded from folders on your system and there is little limit to their number (thousands ought be no problem).

Features:
* Shows Images - The simple most obvious core of a slide-show.  Any of the image types supported by the OBS-Studio Image source can be used and an Image view duration time is user selected.
* Plays Videos - Just like showing pictures, Videos play but they play for the duration of the Video while Pictures show for a designated time period. Any of the media types supported by the OBS-Studio Media source can be used although Video/Visual types are the most logical. 
* Managed Background Audio. A Background Audio source volume can be faded by percent while Videos are shown. Volume is transitioned back to normal when Video(s) complete.
* Near unlimited Media files possible. Media files are loaded between source deactivation's / activation's. Original design intent was to support thousands.
* Multi-Scene work-flow like capabilities. Each Media File Collection entry is associated with a Scene and each one can optionally define a Next-Scene. This enables the creation of an automated switching from scene to scene for as many entries as defined.
* Co-exists with OBS-Studio configured Show/Hide transitions. Image visibility duration takes into consideration Image Source show/hide transition times. 
* Optionally shows each full/partial file specification in a Text source during a show. 
* Capable of Starting and Stopping Recording Automatically.  This feature also acts to Fade the optional Background Audio source in at recording start and fade out at recording end.

All this and more. This script was developed for Linux and tested on Windows. Aside from platform specifics, it works identically on either. MacOS is expected to just work.

The basic inspiration for this software is multi-faceted.  First, came the discovery of OBS-Studio and then came the understanding of the deficiencies of the built-in Image-Slide-Show source and other script based efforts that attempted to do better/more.  I have also been programming since the PDP-11 days (~1977) and am now semi retired.  I still itched to program but needed something worthy and interesting to latch onto.  Personally, I wanted to take thousands of pictures, scanned from many boxes of old family photos and make them available to the family in a format that they would actually enjoy viewing as well as without distributing a large zip file that folks are not likely to reaaly look at.  I figured that presenting them in a grand homemade video with both audio/video narration and background Music etc would be attractive and useful for all.  I also wanted sometihg that I could build up Chapter by Chapter and finally press a button and have OBS-Studio just run the whole show in an automated way, including the starting and stopping of the recording.  I could start it, go have a long dinner and come back and it would be done.

Thus, the SuperMediaSlideShow script program for OBS-Studio allows me to acheive this goal.  It has been a great learning experience.  This has been an enjoyable endulgence in Lua as well as doing things that were different from the usual kinds of things done in the past. Lastly, I want to extend a mulitude of Thanks to all in the OBS-Studio lua community from which I was able to draw on tips and tricks to make it happen.
