using UnityEngine;

namespace CodexWater
{
    [DisallowMultipleComponent]
    public class WaterwayEffect : MonoBehaviour
    {
        [Header("Source / 水道模型")]
        public MeshFilter source;
        public bool restore300MeterSpan = false;
        [Header("Waterfalls / 两侧瀑布")]
        [Min(.2f)] public float waterfallHeight = 6f;
        [Range(0f,3f)] public float outwardSpread = .8f;
        public bool leftWaterfall = true;
        public bool rightWaterfall = true;
        public bool particles = true;
        [Range(.1f,2f)] public float particleDensity = 1f;
        [Header("Materials / 材质")]
        public Material surfaceMaterial;
        public Material waterfallMaterial;
        public Material mistMaterial;
        public Material sprayMaterial;
        [HideInInspector] public float centerlineLength;
        [HideInInspector] public float sourceSpan;
        [HideInInspector] public Renderer originalRenderer;
        [HideInInspector] public bool originalRendererEnabled;

        public void PlayParticles()
        {
            foreach (var p in GetComponentsInChildren<ParticleSystem>()) p.Play();
        }
        public void StopParticles()
        {
            foreach (var p in GetComponentsInChildren<ParticleSystem>()) p.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        }
    }
}
