# Godot Motion Blur Addon
The latest iteration of my motion blur implementation for godot, including a technical walkthrough.

## Guide

### Installation
1. Install the [Easy Compositor Addon](https://github.com/sphynx-owner/Easy-Compositor-Addon), it's a dependency.
2. Download the code as a zip file (or download the latest release if there's any).
3. Copy the folder `./addons/godot-motion-blur` and paste it under `res://addons/` in your Godot project.
4. Go to **Project**->**Project Settings**->**Plugins** and ensure that the *Godot Motion Blur* plugin is enabled.

### How To Use
1. Add a **GuertinSphynxMotionBlur** compositor effect to your active compositor. It should start working right away.

### Additional Features
To be written

## Background

Disclaimer: You can skip this section and jump straight to **Technical Overview**.

A few years back the Godot development team reached out to the community to create a workgroup that would develop Godot's motion blur.

I enjoy the world of graphics programming, and with little experience and a lot of confidence, marched in to what I know today was a way-over-my-head task.

It was fun, don't get me wrong, but I simply was not equipped to be able to produce something that I could say Godot deserved.

I ended up finding a cool way to dilate velocities for motion blur, and fixated on it for way too long. Only later did I realize that velocity dilation is far from the only thing that makes a motion blur effect great.

Combine that with a relatively limited understanding of Godot (and programming in general), and you have the disasterously messy repository that's the [JFA driven motion blur addon](https://github.com/sphynx-owner/JFA_driven_motion_blur_addon) repo.

Nevertheless, it was pretty popular and is still a go to for people who want to add motion blur in their Godot projects.

A year or so pass, and efforts to add the motion blur natively to Godot were rejuvinated. This time it was serious, people were volunteering to take on it, and were asking technical questions.

The existing motion blur repository was not approachable for someone wanting to port it into the engine, so with the little time I had, I compiled the [godot motion blur addon simplified](https://github.com/sphynx-owner/godot-motion-blur-addon-simplified) repo.

It was a big improvement over the previous, more popular repo. The older repo was bloated with multiple motion blur methods that were not of interest, and everything was very ad-hoc, making it impossible to extract a coherent implementation out of.

This new repository was cleaned up, fat trimmed, and only contained the desired motion blur pipeline. But it could have been better. Still, [**@HydrogenC**](https://github.com/HydrogenC) and [**@DaveTheEggMan**](https://github.com/DaveTheEggman) rolled with it and created an amazing native Godot implementation of it in [this PR](https://github.com/godotengine/godot/pull/115027).

Due to lack of time I could not focus as much as I would have liked on polishing the effect, so when the time came considering merging it, it fell short.

I now have some time, and this addon is the result. It aims to be a reference for engine maintainers in hopes of proving its feasibility as a native engine feature. If it does not end up achieving that, it could be the new-and-improved motion blur addon for Godot.

## Technical Overview

### What Is Motion Blur

Motion blur is an artifact resulting from **the averaging of perceived light over a period of time**.

<video controls src="readme_assets/blur_accumulation.mp4" title="Title"></video>

### Real-Time Post-Process Motion Blur is Different

A practical real-time motion blur effect does not have the luxury of averaging the color of a scene at multiple points in time, as it would require multiple render passes. Instead we slightly skew our definition of motion blur, to be from the perspective of the viewed elements.

Instead of saying that motion blur is the average of color over a period of time, we can say that it's the smearing and dilution (losing opacity) of objects along their motion over a period of time.

This is what the motion blur effect in this addon does.

Let's say this is our input:

![alt text](readme_assets/playground_1_plain_color.png)

You can mentally divide the way this real-time motion blur works into 2 distinct processes:

1. Smearing the current object's color. It uses the velocities directly written by the object, so it's confined to the object's silhouette. In addition to smearing the object's color, it accepts any color from geometry that's further from the camera than the object, achieving "fake transparency".
![alt text](readme_assets/playground_1_x_weight_only.png)

2. Accepting the extended blur of other objects. This requires some form of velocity dilation, which is the process of extending dominant velocities in the velocity texture beyond their original silhouettes. This dilated velocity texture is then used to "search" for objects that match that velocity and are closer to the camera than the current object, and blur them on top of it. In this example, the back wall sees dominant velocities from the cube, and collects color from it onto itself.
![alt text](readme_assets/playground_1_y_weight_only.png)

When designed to naturally complete each other, combining them results in a seamless and believable approximation.
![alt text](readme_assets/playground_1_combined_weights.png)


### Godot's limitations

Godot provides us with a motion-vectors texture, and it's not without its caveats:

- The user has no control over them, so they cannot be selectively disabled or enabled for individual meshes (custom motion vector support is in the works).
- Motion vectors are not written for background and skyboxes
- Some render settings like enabling FSR2 modify how these motion vectors behave.
- Motion vectors are in UV space and in practice just point to the previous UV of the object.
- As of now there are glitches with objects that are spawned in, and sharp direction changes of the camera movement.
- If the camera moves backwards really fast along a surface, you can see velocity vectors that point to a position behind the camera's near clip plane. This leads to these velocities being flipped, and in addition results in asymptotical behavior the closer these previos positions are to the near clip plane.

I am solving some of these issues in this addon.

### The Pipeline

This is the pipeline of the effect:

![alt text](<readme_assets/motion blur pipeline.drawio.png>)

It uses the scene data buffer and depth, velocity and color textures provided by Godot. In addition it uses a texture to store custom processed velocities and depth, 2 textures to generate neighbor_max information and an output color texture.

There are 5 compute stages in the pipeline:

1. **Pre Processing** - Takes the depth and velocity textures, as well as scene data, and Generates a processet velocity-depth texture with improved velocity and depth information. It's most crucial functionality is adding motion vectors to background pixels.

2. **Tile Max X** - Finds and stores the largest velocity in each tile's row.

3. **Tile Max Y** - Takes the result of Tile Max X, and performs a similar process, now vertically, resulting in a pixel-per-tile texture of the largest velocity found in each tile (Tile Max).

4. **Neighbor Max** - Takes the Tile Max texture, and output a Neighbor Max texture, each pixel now containing the largest velocity found in each tile and its neighbors.

5. **Motion Blur** - Takes the Neighbor Max texture, the processed velocitiy-depth texture, and Godot's color texture, and generates a motion blur approximation onto a Color Output texture.

The pipeline uses Godot's depth, color and velocity textures, and 4 additional custom textures:

1. **processed velocity-depth** `rgba16f | size = (render_size.x, render_size.y)` - stores the result of the Pre Processing stage.

2. **tile max x / neighbor max** `rg8i | size = (render_size.x / tile_size, render_size.y)` - stores both the result of the Tile Max X stage, and then used again to store the result of the Neighbor Max stage. 

3. **tile max** `rg8i | size = (render_size.x / tile_size, render_size.y / tile_size)` - stores the result of the Tile Max Y stage.

4. **color output** `rgba16f | size = (render_size.x, render_size.y)` - stores the output of the Motion Blur stage

### Pre Processing Stage



### Tile Max X Stage

### Tile Max Y Stage

### Neighbor Max Stage

### Motion Blur Stage