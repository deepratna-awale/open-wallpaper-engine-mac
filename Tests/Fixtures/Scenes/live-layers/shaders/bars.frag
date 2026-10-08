uniform float g_AudioSpectrum16Left[16];
varying vec2 v_TexCoord;
void main() {
	gl_FragColor = vec4(step(v_TexCoord.y, g_AudioSpectrum16Left[int(v_TexCoord.x * 15.0)]));
}
