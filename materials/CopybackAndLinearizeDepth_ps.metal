#include <metal_stdlib>
using namespace metal;

struct PS_INPUT
{
    float2 uv0;
    float3 cameraDir;
};

struct Params
{
    float2 projectionParams;
    float farClipDistance;

};

fragment float main_metal
(
	PS_INPUT inPs [[stage_in]],
    float4 gl_FragCoord [[position]],

	texture2d<float, access::read>      depthTexture    [[texture(0)]],
 
    constant Params &p [[buffer(PARAMETER_SLOT)]]
)
{
    float depth = depthTexture.read( uint2( gl_FragCoord.xy ), 0 ).x;
    
    float linearDepth = p.projectionParams.y / (depth - p.projectionParams.x);
    
    float3 rayOriginVS = inPs.cameraDir.xyz * linearDepth;
    
    return -rayOriginVS.z;  // think this is linear so mipmapping and bilinear filter will work correctly
    //return linearDepth;
}
