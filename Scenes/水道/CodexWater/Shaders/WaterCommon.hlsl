#ifndef CODEX_WATER_COMMON_INCLUDED
#define CODEX_WATER_COMMON_INCLUDED
float WaterEyeDepth(float rawDepth)
{
    if (unity_OrthoParams.w > .5)
    {
        #if UNITY_REVERSED_Z
        rawDepth = 1.0 - rawDepth;
        #endif
        return lerp(_ProjectionParams.y, _ProjectionParams.z, rawDepth);
    }
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}
#endif
