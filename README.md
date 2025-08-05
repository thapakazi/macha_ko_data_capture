# RGB-D Data Capture App for iPhone TrueDepth Camera


> The code is modified from Apple Sample Code: https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/streaming_depth_data_from_the_truedepth_camera

> Hardware requirements: Mac OS with Xcode 11.0+, iPhone with TrueDepth Camera and iOS 12.0+


## Build and Run

You need a **Mac OS with Xcode 11.0+** to build the code and an **iPhone with TrueDepth Camera**, e.g., iPhone X or newer, to run the program. 

To build the code, open the project with Xcode, and you should be able to compile it. After building it successfully, connect your iphone and install it. 

You will see something like below on your iphone. 

**NEW FEATURES**:
- **Manual Capture Mode**: The app now features a blue "Capture" button for manual RGB-D image capture
- **Camera Calibration Data**: Each capture saves camera calibration data including:
  - Intrinsic matrix (fx, fy, cx, cy)
  - Extrinsic matrix
  - Reference dimensions
  - Video dimensions
  - Pixel size/scale
  - Lens distortion parameters
- **Calibration data is saved as JSON files** in the app's documents directory with timestamp

**NOTE**: The app is now in manual capture mode by default. Press the "Capture" button to save RGB-D images and calibration data.
<div>
<div align=center><img src="figures/screen1.jpg" alt="img" width=30%>
</div>


The captured RGB-D images will be saved in the album, like the snapshot below. Then you can freely export them from the album.

<div>
<div align=center><img src="figures/screen.jpg" alt="img" width=30%>
</div>


## Capturing Human Faces

There is a guidance circle on the interface for capturing face images. In order to collect the depth of a face better, we recommend that the face should be close to the screen until **the face is about the same size as the guidance circle**, as shown below.

<div>
<div align=center><img src="figures/circle.jpg" alt="img" width=30%>
</div>
 

