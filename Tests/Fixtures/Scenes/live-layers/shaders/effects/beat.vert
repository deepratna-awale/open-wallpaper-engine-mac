// [COMBO] {"material":"Audio response","combo":"AUDIOPROCESSING","type":"audioprocessingoptions","default":0}
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
#if AUDIOPROCESSING
uniform float g_AudioSpectrum16Left[16];
#endif
void main() {
	float scale = 1.0;
#if AUDIOPROCESSING
	scale += g_AudioSpectrum16Left[0];
#endif
	gl_Position = mul(vec4(a_Position * scale, 1.0), g_ModelViewProjectionMatrix);
}
