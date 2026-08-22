#pragma once
#include "imgui/imgui.h"
#include "imgui/imgui_internal.h"
#include <atomic>
#include <cmath>
#include <thread>
#include <cstdint>
extern "C" void* run_thread(void* arg);
static inline ImU32 LerpColor(ImU32 a, ImU32 b, float t){
ImVec4 ca=ImGui::ColorConvertU32ToFloat4(a);
ImVec4 cb=ImGui::ColorConvertU32ToFloat4(b);
ImVec4 r;
r.x=ca.x+(cb.x-ca.x)*t;
r.y=ca.y+(cb.y-ca.y)*t;
r.z=ca.z+(cb.z-ca.z)*t;
r.w=ca.w+(cb.w-ca.w)*t;
return ImGui::ColorConvertFloat4ToU32(r);
}
static inline float LerpF(float a,float b,float t){return a+(b-a)*t;}
struct HoloToggleState{
std::atomic<bool> isActive{false};
float anim=0.0f;
};
static inline bool HoloToggle(const char* label,HoloToggleState& state,const ImVec2& size=ImVec2(220,50),int threadID=-1,bool* pChanged=nullptr){
ImGuiWindow* window=ImGui::GetCurrentWindow();
if(!window||window->SkipItems){
if(pChanged)*pChanged=false;
return state.isActive.load();
}
ImGui::PushID(label);
ImGui::BeginGroup();
ImDrawList* draw=ImGui::GetWindowDrawList();
const ImVec2 p_min=ImGui::GetCursorScreenPos();
float time=ImGui::GetTime();
const float W=size.x;
const float H=size.y;
const float corner_radius=H*0.15f;
const float knob_radius=(H*0.5f)*0.82f;
ImGui::InvisibleButton("##holo_toggle",ImVec2(W,H));
const ImVec2 p_max=ImVec2(p_min.x+W,p_min.y+H);
const ImVec2 center=ImVec2((p_min.x+p_max.x)*0.5f,(p_min.y+p_max.y)*0.5f);
bool value_changed=false;
if(ImGui::IsItemClicked()){
bool cur=state.isActive.load();
state.isActive.store(!cur);
value_changed=true;
}
const float target=state.isActive.load()?1.0f:0.0f;
const float speed=9.0f;
float dt=ImGui::GetIO().DeltaTime;
if(dt<=0.0f)dt=1.0f/60.0f;
state.anim=LerpF(state.anim,target,ImMin(1.0f,dt*speed));
const float t=(state.anim<=0.0f)?0.0f:powf(state.anim,0.4f);
const ImU32 col_plate_shadow=IM_COL32(6,8,10,200);
const ImU32 col_plate_edge=IM_COL32(28,32,36,255);
const ImU32 col_text_off=IM_COL32(255,100,100,255);
const ImU32 col_knob_off_base=IM_COL32(100,20,30,255);
const ImU32 col_knob_off_mid=IM_COL32(180,30,40,220);
const ImU32 col_knob_off_core=IM_COL32(255,80,90,200);
const ImU32 col_glow_off=IM_COL32(200,40,50,110);
const ImU32 col_inner_line_off=IM_COL32(140,20,30,255);
const ImU32 col_text_on=IM_COL32(80,255,120,255);
const ImU32 col_knob_on_base=IM_COL32(10,100,30,255);
const ImU32 col_knob_on_mid=IM_COL32(30,160,60,220);
const ImU32 col_knob_on_core=IM_COL32(80,255,120,200);
const ImU32 col_glow_on=IM_COL32(50,220,100,140);
const ImU32 col_inner_line_on=IM_COL32(20,140,50,255);
ImU32 textColor=LerpColor(col_text_off,col_text_on,t);
ImU32 knobBase=LerpColor(col_knob_off_base,col_knob_on_base,t);
ImU32 knobMid=LerpColor(col_knob_off_mid,col_knob_on_mid,t);
ImU32 knobCore=LerpColor(col_knob_off_core,col_knob_on_core,t);
ImU32 glowColor=LerpColor(col_glow_off,col_glow_on,t);
ImU32 innerLineColor=LerpColor(col_inner_line_off,col_inner_line_on,t);
ImVec2 shadowOffset=ImVec2(0.0f,H*0.06f);
draw->AddRectFilled(ImVec2(p_min.x+2+shadowOffset.x,p_min.y+2+shadowOffset.y),ImVec2(p_max.x+2+shadowOffset.x,p_max.y+2+shadowOffset.y),col_plate_shadow,corner_radius);
draw->AddRectFilled(p_min,p_max,col_plate_edge,corner_radius);
const float inset=H*0.08f;
const ImVec2 inner_p_min=ImVec2(p_min.x+inset,p_min.y+inset);
const ImVec2 inner_p_max=ImVec2(p_max.x-inset,p_max.y-inset);
auto SilverShade=[&](float offset){return(int)(180+50*(0.5f+0.5f*sinf(time*0.8f+offset)));};
ImU32 colorBlack=IM_COL32(15,15,15,255);
ImU32 colorSilver1=IM_COL32(SilverShade(0.0f),SilverShade(1.0f),SilverShade(2.0f),255);
ImU32 colorSilver2=IM_COL32(SilverShade(3.0f),SilverShade(4.0f),SilverShade(5.0f),255);
draw->AddRectFilledMultiColor(inner_p_min,inner_p_max,colorBlack,colorSilver1,colorBlack,colorSilver2);
draw->AddRect(inner_p_min,inner_p_max,innerLineColor,corner_radius-(inset/2.0f),0,1.25f);
const float leftX=p_min.x+H*0.5f;
const float rightX=p_max.x-H*0.5f;
const float knobX=LerpF(leftX,rightX,t);
ImVec2 knobCenter=ImVec2(knobX,center.y);
draw->AddCircleFilled(knobCenter,knob_radius+H*0.16f*(0.6f+0.4f*t),glowColor,32);
draw->AddCircle(knobCenter,knob_radius+H*0.06f,IM_COL32(16,18,20,220),32,H*0.06f);
draw->AddCircle(knobCenter,knob_radius+H*0.03f,IM_COL32(40,46,52,255),32,H*0.04f);
draw->AddCircleFilled(knobCenter,knob_radius,knobBase,48);
draw->AddCircleFilled(knobCenter,knob_radius*0.78f,knobMid,48);
draw->AddCircleFilled(knobCenter,knob_radius*0.48f,knobCore,48);
draw->AddCircle(knobCenter,knob_radius*0.78f,textColor,48,H*0.03f);
for(int i=0;i<5;++i){
float pct=i/5.0f;
float y=knobCenter.y-knob_radius*0.6f+pct*(knob_radius*0.28f);
float radius=knob_radius*(0.9f-pct*0.6f);
draw->AddCircleFilled(ImVec2(knobCenter.x-knob_radius*0.12f,y),radius,IM_COL32(255,255,255,25),24);
}
ImFont* font=ImGui::GetFont();
float fontSize=H*0.4f;
float textAreaW=W-H-(H*0.2f);
ImVec2 textSize=ImGui::CalcTextSize(label,NULL,false,textAreaW);
ImVec2 textPos=ImVec2(p_min.x+(textAreaW-textSize.x)*0.5f+(H*0.1f),center.y-textSize.y*0.5f);
draw->AddText(font,fontSize,ImVec2(textPos.x+1,textPos.y+1),IM_COL32(0,0,0,150),label);
draw->AddText(font,fontSize,textPos,textColor,label);
ImGui::EndGroup();
ImGui::PopID();
if(value_changed&&threadID!=-1){
int id=threadID;
std::thread([id](){
void* arg=reinterpret_cast<void*>(static_cast<intptr_t>(id));
run_thread(arg);
}).detach();
}
if(pChanged)*pChanged=value_changed;
return state.isActive.load();
}
