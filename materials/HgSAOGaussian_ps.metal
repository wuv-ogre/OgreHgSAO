#include <metal_stdlib>
using namespace metal;

#define OUTLINE_DEPTH 0.1
#define OUTLINE_NORMAL 0.2

constexpr constant float c_wt_coef[16] =
{
    0.0920246, 0.0902024, 0.0849494, 0.0768654, 0.0668236, 0.0558158, 0.0447932, 0.0345379
};

struct PS_INPUT
{
	float2 uv0;
};

struct Params
{
    uint2 step;
    float4 viewportSize;
};


bool sameArea ( float depth0, float3 normal0, float depth, float3 normal )
{
    float edgeDepthThreshold = min( OUTLINE_DEPTH + 0.05f * max( depth0 - 20.0f, 0.0f ), 7.0f );
    float3 diff = abs( normal0 - normal );
    return (abs(depth0 - depth) < edgeDepthThreshold && diff.x < OUTLINE_NORMAL && diff.y < OUTLINE_NORMAL && diff.z < OUTLINE_NORMAL);
}

fragment float4 main_metal
(
	PS_INPUT inPs [[stage_in]],
	float4 gl_FragCoord [[position]],
 
	texture2d<float, access::read>      depthTexture    [[texture(0)]],
    texture2d<float, access::read>      gBuf_normals    [[texture(1)]],
    texture2d<float, access::read>      occlusion       [[texture(2)]],
 
    constant Params &p [[buffer(PARAMETER_SLOT)]]
 )
{
    
    uint2 iCoords0 = uint2( gl_FragCoord.xy);
    
    float depth0 = depthTexture.read( iCoords0 ).x;
    float3 normal0 = /*normalize*/( gBuf_normals.read( iCoords0 ).xyz * 2.0f - 1.0f );
    

    
    float ao = occlusion.read( iCoords0 ).x;
    float sum = c_wt_coef[0] * ao;
    float sumRate = c_wt_coef[0];

    for( int i=1; i<8; i++ )
    {
        // when iCoords outside the limits of viewport.xy presumably will be sampling black.

        
        uint2 iCoords = iCoords0 - p.step * i;
        
        float  depth = depthTexture.read( iCoords ).x;
        float3 normal = /*normalize*/( gBuf_normals.read( iCoords ).xyz * 2.0f - 1.0f );

        if( sameArea( depth0, normal0, depth, normal ) )
        {
            ao = occlusion.read( iCoords ).x;
            sum += c_wt_coef[i] * ao;
            sumRate += c_wt_coef[i];
        }
        
        iCoords = iCoords0 + p.step * i;
        
        depth = depthTexture.read( iCoords ).x;
        normal = /*normalize*/( gBuf_normals.read( iCoords ).xyz * 2.0f - 1.0f );
        
        if( sameArea( depth0, normal0, depth, normal ) )
        {
            ao = occlusion.read( iCoords ).x;
            sum += c_wt_coef[i] * ao;
            sumRate += c_wt_coef[i];
        }
    }
    
    ao = sum/sumRate;
    
    return float4( float3( ao ), 1.0 );
}
