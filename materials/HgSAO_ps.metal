#include <metal_stdlib>
using namespace metal;

#define INLINE inline
#define PARAMS_ARG_DECL , constant Params &p
#define PARAMS_ARG , p
#define TEXTURES_ARG_DECL , texture2d<float, access::read> depthTexture
#define TEXTURES_ARG , depthTexture


#define USE_MSAA 0
#define SCREEN_SIZE_RATIO 1.0
#define SAMPLE_COUNT 15
#define NUM_SPIRAL_TURNS 7
#define LOG_MAX_OFFSET 3
#define MAX_MIP_LEVEL 5
#define TWO_PI 6.28318530718

struct PS_INPUT
{
	float2 uv0;
	//float3 cameraDir;
};

struct Params
{
    float2 projectionParams;
    float4 viewportSize;
    float4x4 projectionMatrix;
    float4x4 inverseProjectionMatrix;
    float ssScale;
    float radius;
    float bias;
    float intensity;
};


INLINE float linearizeDepth( float fDepth PARAMS_ARG_DECL )
{
    return p.projectionParams.y / (fDepth - p.projectionParams.x);
}


#if !USE_MSAA
	INLINE float3 loadSubsample0( texture2d<float, access::read> tex, float2 iCoords )
	{
		return tex.read( uint2( iCoords ), 0 ).xyz;
	}
#else
	INLINE float3 loadSubsample0( texture2d_ms<float, access::read> tex, float2 iCoords )
	{
		return tex.read( uint2( iCoords ), 0 ).xyz;
	}
#endif


INLINE float readMip( texture2d<float, access::read> tex, float2 iCoords, int lod )
{
    return tex.read( uint2( iCoords / pow(2.0, lod) ), lod ).x;
}


INLINE float readMip( texture2d<float> tex, sampler samplerBilinear, float2 iCoords, int lod )
{
    return  tex.sample( samplerBilinear, iCoords, level(lod) ).x;
}



float3 VSFromDepth(float depth, float2 uv, float4x4 projectionMatrix, float4x4 inverseProjectionMatrix)
{
    float viewZ = -depth;
    float z_ndc = ( viewZ * projectionMatrix[2].z + projectionMatrix[3].z ) / -viewZ;
    
    // Get x/w and y/w from the viewport position
    float x = uv.x * 2.0 - 1.0;
    
    float y = (1.0 - uv.y) * 2.0 - 1.0;     // directX and metal
    //float y = uv.y * 2.0 - 1.0;           // glsl
    
    // NDC (normalised device coordinates) runs from -1..1, in X, Y, and Z.
    float4 ndc = float4(x, y, z_ndc, 1.0);
    
    float4 projPos = inverseProjectionMatrix * ndc;
    
    // Divide by w to get the view-space position
    return projPos.xyz / projPos.w;
}


fragment float4 main_metal
(
	PS_INPUT inPs [[stage_in]],
	float4 gl_FragCoord [[position]],
 
	//texture2d<float, access::read>      depthTexture    [[texture(0)]],
	texture2d<float>                    depthTexture    [[texture(0)]],
#if !USE_MSAA
    texture2d<float, access::read>      gBuf_normals    [[texture(1)]],
#else
    texture2d_ms<float, access::read>   gBuf_normals    [[texture(1)]],
#endif

    texture2d<float, access::read>      randomNoise     [[texture(2)]],
 
    sampler                             samplerBilinear	[[sampler(0)]],

 
    constant Params &p [[buffer(PARAMETER_SLOT)]]
 )
{
    float3 normalVS = normalize( loadSubsample0( gBuf_normals, gl_FragCoord.xy ).xyz * 2.0f - 1.0f );

    // uvs don't look like they do in glsl
    float2 uv0 = inPs.uv0;


    float depth = depthTexture.sample( samplerBilinear, uv0 ).x;    // view space z
    
    //float depth = depthTexture.read( uint2( gl_FragCoord.xy ), 0 ).x;
    //float linearDepth = depth; //linearizeDepth( depth PARAMS_ARG );
    
    //float3 rayOriginVS = inPs.cameraDir.xyz * depth;
    float3 rayOriginVS = VSFromDepth( depth, uv0, p.projectionMatrix, p.inverseProjectionMatrix );
    
    
    float2 viewportPixelSize = p.viewportSize.xy;
    float2 workViewportSize = floor( viewportPixelSize * SCREEN_SIZE_RATIO );
    //float2 trueScnScale = workViewportSize / viewportPixelSize;

    // SS for screen space
    int2 posSS = int2( gl_FragCoord.xy );

    //float randomAngle = (5.0f * float(posSS.x % posSS.y) + posSS.x * posSS.y ) * 7.0f;
    float randomAngle = randomNoise.read( uint2( gl_FragCoord.xy ) % 1024 ).x * TWO_PI;

    float diskRadiusSS = p.ssScale * p.radius / rayOriginVS.z;
    
    float radiusSq = p.radius * p.radius;

    float sum = 0.0f;
    for (int sampleIndex = 0; sampleIndex < SAMPLE_COUNT; sampleIndex++)
    {
        float alpha = float( sampleIndex + 0.5f ) / SAMPLE_COUNT;
        float angle = alpha * ( NUM_SPIRAL_TURNS * TWO_PI ) + randomAngle;
        float radiusSS = alpha * -diskRadiusSS ;
        float2 unitOffset = float2( cos(angle), sin(angle) ) * radiusSS;
        
        float2 px = float2( posSS ) + unitOffset;
        float2 uv = px / workViewportSize;
        
        int lod = clamp( int( floor( log2( radiusSS ) ) ) - LOG_MAX_OFFSET, 0, MAX_MIP_LEVEL );

        float depthSS = readMip( depthTexture, samplerBilinear, uv, lod );

        float3 offsetVS = VSFromDepth( depthSS, uv, p.projectionMatrix, p.inverseProjectionMatrix );
        
        float3 v = offsetVS - rayOriginVS;
        
        float vv = dot(v, v);
        float vn = dot(v, normalVS);
        
        const float epsilon = 0.01f;
        float f = max( radiusSq - vv, 0.0f );
        
        float ao = f * f * f * max( ( vn - p.bias ) / ( epsilon + vv ), 0.0f );
        
        sum += ao;
        
        //if(sampleIndex == 10) { return float4( float3(lod)/ float(MAX_MIP_LEVEL), 1.0 ); }
    }
    


    float radius3 = radiusSq * p.radius;
    sum /= radius3 * radius3;

    float ao = max( 0.0f, 1.0f - sum * p.intensity * ( 5.0f / SAMPLE_COUNT ) );
    
    return float4( float3( 1.0f-ao ), 1.0 );
}
