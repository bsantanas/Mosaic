//
//  Kernels.metal
//  Mosaic
//
//  Created by Bernardo Santana on 10/19/16.
//  Copyright © 2016 Bernardo Santana. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

kernel void pixelate(texture2d<float, access::read> inTexture [[texture(0)]],
                     texture2d<float, access::write> outTexture [[texture(1)]],
                     device unsigned int *pixelSize [[buffer(0)]],
                     uint2 gid [[thread_position_in_grid]])
{
    const uint2 pixellateGrid = uint2((gid.x / pixelSize[0]) * pixelSize[0], (gid.y / pixelSize[0]) * pixelSize[0]);
    const float4 colorAtPixel = inTexture.read(pixellateGrid);
//    const float4 colorAtPixel = inTexture.read(gid);
    outTexture.write(colorAtPixel, gid);
}


kernel void YCbCrColorConversion(texture2d<float, access::read> yTexture [[texture(0)]],
                                 texture2d<float, access::read> cbcrTexture [[texture(1)]],
                                 texture2d<float, access::write> outTexture [[texture(2)]],
                                 uint2 gid [[thread_position_in_grid]])
{
    float3 colorOffset = float3(-(16.0/255.0), -0.5, -0.5);
    float3x3 colorMatrix = float3x3(
                                    float3(1.164,  1.164, 1.164),
                                    float3(0.000, -0.392, 2.017),
                                    float3(1.596, -0.813, 0.000)
                                    );
    
    uint2 cbcrCoordinates = uint2(gid.x / 2, gid.y / 2); // half the size because we are using a 4:2:0 chroma subsampling
    
    float y = yTexture.read(gid).r;
    float2 cbcr = cbcrTexture.read(cbcrCoordinates).rg;
    
    float3 ycbcr = float3(y, cbcr);
    
    float3 rgb = colorMatrix * (ycbcr + colorOffset);
    
    outTexture.write(float4(float3(rgb), 1.0), gid);
}
