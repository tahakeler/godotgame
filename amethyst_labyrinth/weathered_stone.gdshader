shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2D palette : source_color, filter_nearest;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap_anisotropic;
varying vec3 world_pos;
varying vec3 world_n;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;world_n=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
float noise3(vec3 p, vec3 w){return dot(vec3(texture(grain,p.yz).r,texture(grain,p.xz).r,texture(grain,p.xy).r),w);}
float block(vec2 p){
 float row=floor(p.y/0.52);
 vec2 q=vec2(p.x+mod(row,2.0)*0.53,p.y);
 vec2 f=fract(q/vec2(1.06,0.52));
 vec2 edge=min(f,1.0-f)*vec2(1.06,0.52);
 return smoothstep(0.006,0.028,min(edge.x,edge.y));
}
float relief(vec3 p,vec3 w){return noise3(p*0.4,w)*0.012+noise3(p*2.0,w)*0.0015+(block(p.zy)*w.x+block(p.xy)*w.z)*0.018;}
void fragment(){
 vec3 wn=normalize(world_n);vec3 w=pow(abs(wn),vec3(8.0));w/=max(w.x+w.y+w.z,0.0001);
 vec3 c=texture(palette,UV).rgb;
 float n=noise3(world_pos*0.4,w);float broad=noise3(world_pos*0.075,w);
 float stone=step(c.r*0.95,c.b);
 float mortar=block(world_pos.zy)*w.x+block(world_pos.xy)*w.z+w.y;
 vec3 stone_col=c*mix(0.66,1.08,n)*mix(0.65,1.0,mortar);
 float base_damp=(1.0-smoothstep(0.05,1.4,world_pos.y))*smoothstep(0.35,0.65,broad);
 stone_col=mix(stone_col,stone_col*vec3(0.43,0.49,0.42),base_damp*0.55);
 vec3 earth=mix(c,vec3(dot(c,vec3(0.3,0.5,0.2)))*vec3(0.8,0.72,0.6),0.40)*mix(0.7,1.0,n);
 ALBEDO=mix(earth,stone_col,stone);
 ROUGHNESS=mix(0.94,0.62,base_damp*stone);SPECULAR=0.28;
 float e=0.007;float h=relief(world_pos,w);
 vec3 g=vec3(relief(world_pos+vec3(e,0,0),w)-h,relief(world_pos+vec3(0,e,0),w)-h,relief(world_pos+vec3(0,0,e),w)-h)/e;
 g-=wn*dot(g,wn);NORMAL=normalize(NORMAL-(VIEW_MATRIX*vec4(g,0)).xyz*mix(0.20,0.65,stone));
}
