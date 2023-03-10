# Notes on WEBGPU

## Swap-chain

Generally there are is array/chain of >=2 frames-buffers, One frame-buffer is called screen-buffer and rest of others are called back-buffers.
- Screen-buffer: This frame-buffer is the one that is going to be shown on the screen.
- Back-buffer: This frame-buffer is the one application is going to render on.
So, when you request swap-chain from frame-buffer for you to draw on (`swapChain().getCurrentTextureView()`), it will give you one of the available back-buffer, and when you present it (`swapChain().present()`), it will swap your back-buffer (that you drew on) with your screen buffer and so, whatever you drew will be rendered on screen. And this way, your previous screen-buffer will now become a back-buffer for you to draw on and your previous back-buffer (that you drew on) will become screen-buffer.