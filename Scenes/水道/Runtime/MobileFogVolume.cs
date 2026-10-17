using UnityEngine;

namespace CodexMobileVolumeFog
{
    [ExecuteAlways, DisallowMultipleComponent]
    public sealed class MobileFogVolume : MonoBehaviour
    {
        public static MobileFogVolume Active { get; private set; }
        [Header("轻量体积雾 / 手机预设")]
        public Color fogColor = new Color(.72f, .79f, .83f, 1);
        [Tooltip("雾的浓度；建议 0.01 到 0.025。")]
        [Range(0, .08f)] public float density = .018f;
        [Range(0, .85f)] public float maximumOpacity = .55f;
        [Tooltip("相机附近保持清晰的距离，单位米。")]
        [Min(0)] public float clearDistance = 16;
        [Range(0, .3f)] public float driftAmount = .1f;
        [Range(0, .2f)] public float driftSpeed = .025f;
        [Tooltip("雾体半径，单位米；上下左右平滑淡出。旋转不影响此轴对齐雾体。")]
        public Vector3 radii = new Vector3(200, 24, 200);
        public bool showInSceneView = true;
        void OnEnable() { Active = this; }
        void OnDisable() { if (Active == this) Active = null; }
        void OnValidate() { radii = Vector3.Max(radii, Vector3.one); }
        void OnDrawGizmosSelected()
        {
            Gizmos.color = new Color(.6f, .85f, 1, .5f);
            Gizmos.matrix = Matrix4x4.TRS(transform.position, Quaternion.identity, radii);
            Gizmos.DrawWireSphere(Vector3.zero, 1);
        }
    }
}
