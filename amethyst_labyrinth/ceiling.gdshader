shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain:repeat_enable,filter_linear_mipmap_anisotropic;
varying vec3 pos;
void vertex(){pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float joint(vec2 p){float row=floor(p.y/0.8);vec2 q=fract((p+vec2(mod(row,2.0)*0.675,0))/vec2(1.35,0.8));vec2 d=min(q,1.0-q)*vec2(1.35,0.8);return smoothstep(0.007,0.025,min(d.x,d.y));}
float height_at(vec2 p){return joint(p)*0.022+texture(grain,p*0.6).r*0.01;}
void fragment(){
 vec2 uv=pos.xz;float n=texture(grain,uv*0.6).r;float stain=texture(grain,uv*0.07).r;
 float cell=fract(sin(dot(floor(vec2(uv.x+mod(floor(uv.y/0.8),2.0)*0.675,uv.y)/vec2(1.35,0.8)),vec2(127.1,311.7)))*43758.5);
 ALBEDO=mix(vec3(0.13,0.12,0.105),vec3(0.24,0.23,0.21),cell)*mix(0.6,1.0,joint(uv))*mix(0.72,1.08,n)*mix(0.72,1.0,stain);
 ROUGHNESS=mix(0.76,0.96,n);SPECULAR=0.25;
 float e=0.008;float h=height_at(uv);vec3 g=vec3((height_at(uv+vec2(e,0))-h)/e,0,(height_at(uv+vec2(0,e))-h)/e);
 NORMAL=normalize(NORMAL-(VIEW_MATRIX*vec4(g,0)).xyz*0.5);
}
