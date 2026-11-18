using UnityEngine;
public class WastelandFlyCamera:MonoBehaviour {
 public float walkingSpeed=5,lookSpeed=2,collisionRadius=.18f;
 public bool collisionEnabled=true;
 void Update(){
  if(!Input.GetMouseButton(1))return;
  transform.Rotate(Vector3.up,Input.GetAxis("Mouse X")*lookSpeed,Space.World);
  transform.Rotate(Vector3.right,-Input.GetAxis("Mouse Y")*lookSpeed,Space.Self);
  float s=walkingSpeed*Time.deltaTime*(Input.GetKey(KeyCode.LeftShift)?4:1);
  Vector3 move=(transform.right*Input.GetAxis("Horizontal")+transform.forward*Input.GetAxis("Vertical")+Vector3.up*((Input.GetKey(KeyCode.E)?1:0)-(Input.GetKey(KeyCode.Q)?1:0)))*s;
  if(!collisionEnabled){transform.position+=move;return;}
  Vector3 pos=transform.position;
  for(int i=0;i<3&&move.sqrMagnitude>.0000001f;i++){
   RaycastHit hit;float distance=move.magnitude;
   if(!Physics.SphereCast(pos,collisionRadius,move/distance,out hit,distance+.025f,~(1<<4),QueryTriggerInteraction.Ignore)){pos+=move;break;}
   float travel=Mathf.Max(0,hit.distance-.025f);pos+=move/distance*travel;
   move=Vector3.ProjectOnPlane(move*(1-Mathf.Clamp01(travel/distance)),hit.normal);
  }
  transform.position=pos;
 }
}
