#include <metal_stdlib>
using namespace metal;

struct PS_INPUT
{
	float2 uv0;
};

struct Params
{
    float4 viewportSize;
    float scale;
    float luma;
};

float3 RGBtoYCbCr(float3 rgbColor)
{
    return float3(
    // Y
    0.298912f * rgbColor.r + 0.586611f * rgbColor.g + 0.114478f * rgbColor.b,
    // Cb
    -0.168736f * rgbColor.r - 0.331264f * rgbColor.g + 0.5f      * rgbColor.b,
    // Cr
    0.5f      * rgbColor.r - 0.418688f * rgbColor.g - 0.081312f * rgbColor.b);
}

float3 YCbCrtoRGB(float3 YCbCr)
{
    return float3(YCbCr.x - 0.000982f * YCbCr.y + 1.401845f * YCbCr.z,
                  YCbCr.x - 0.345117f * YCbCr.y - 0.714291f * YCbCr.z,
                  YCbCr.x + 1.771019f * YCbCr.y - 0.000154f * YCbCr.z);
}

fragment float4 main_metal
(
	PS_INPUT inPs [[stage_in]],
	float4 gl_FragCoord [[position]],
 
	texture2d<float, access::read>      scene       [[texture(0)]],
    texture2d<float, access::read>      occlusion   [[texture(1)]],
 
    constant Params &p [[buffer(PARAMETER_SLOT)]]
 )
{
    uint2 iCoords0 = uint2( gl_FragCoord.xy);
    
    float3 sceneColor = scene.read( iCoords0 ).xyz;
    
    float ao = occlusion.read( iCoords0 ).x;
    ao += occlusion.read( iCoords0 + uint2(  0,-1 ) ).x;
    ao += occlusion.read( iCoords0 + uint2(  0, 1 ) ).x;
    ao += occlusion.read( iCoords0 + uint2( -1, 0 ) ).x;
    ao += occlusion.read( iCoords0 + uint2(  1, 0 ) ).x;
    ao += occlusion.read( iCoords0 + uint2( -1,-1 ) ).x;
    ao += occlusion.read( iCoords0 + uint2(  1,-1 ) ).x;
    ao += occlusion.read( iCoords0 + uint2( -1, 1 ) ).x;
    ao += occlusion.read( iCoords0 + uint2(  1, 1 ) ).x;
    ao *= 0.1f;

    float3 YCbCr = RGBtoYCbCr( sceneColor );
    
    ao = clamp( 1.0f - 0.05f * p.scale * ao, 0.1f, 1.0f );
    float density = 1.0f / ao;

    float3 color = mix( sceneColor.rgb*ao, sceneColor.rgb, pow( sceneColor.rgb, density  ) );

    YCbCr.x *= ao;
    //return float4( mix( YCbCrtoRGB( YCbCr ), color, p.luma ), 1.0f );
    
    // visualise ao
    return float4( float3(ao), 1.0 );
}
