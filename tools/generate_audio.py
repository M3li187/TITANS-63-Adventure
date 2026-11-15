"""Build original synthetic cabin/SFX and offline LUNA speech (CMU Flite SLT).
Development helper: needs Python/numpy/scipy, ffmpeg and Flite Linux libraries.
The distributed game plays bundled WAV files; no TTS installation is required.
"""
from pathlib import Path
import ctypes,json,wave,subprocess,tempfile,shutil
import numpy as np
from scipy.signal import butter,sosfilt
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/audio';OUT.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(1402);SR=24000

def write_wav(name,samples,sr=SR):
 samples=np.clip(samples,-.95,.95)
 with tempfile.NamedTemporaryFile(suffix='.wav') as f:
  with wave.open(f.name,'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes((samples*32767).astype('<i2').tobytes())
  shutil.copyfile(f.name, OUT/(name+'.wav'))

def tone(freq,t):return np.sin(2*np.pi*freq*t)
def filt(x,cut,kind='lowpass',sr=SR):return sosfilt(butter(3,cut,kind,fs=sr,output='sos'),x)
def envelope(t,d):return np.minimum(t/.012,1)*np.minimum((d-t)/.06,1)
def chime(notes,d=.8):
 t=np.arange(int(SR*d))/SR;y=np.zeros_like(t)
 for i,n in enumerate(notes):
  tt=np.maximum(t-i*.12,0);mask=t>=i*.12;y+=tone(n,tt)*np.exp(-tt*6)*mask*.16
 return y*envelope(t,d)
for name,notes in [('confirm',[660,880]),('success',[523.25,659.25,783.99,1046.5]),('normal',[440,554.37,659.25]),('abort',[523.25,659.25,523.25]),('failure',[311.13,293.66,220]),('comms',[880,1174.66])]:write_wav(name,chime(notes,1.25 if name in ['success','failure'] else .8))
t=np.arange(int(.16*SR))/SR;write_wav('control',.20*tone(1150,t)*np.exp(-t*45)*envelope(t,.16))
t=np.arange(int(.48*SR))/SR;write_wav('step',(filt(rng.normal(0,1,len(t)),650)*.17+tone(95,t)*.08)*np.exp(-t*14)*envelope(t,.48))
t=np.arange(int(1.3*SR))/SR;write_wav('door',(tone(135,t)*.09+tone(270,t)*.035+filt(rng.normal(0,1,len(t)),2100)*.045)*np.sin(np.pi*t/1.3)**.7)
t=np.arange(int(.8*SR))/SR;alarm=np.zeros_like(t)
for start in [.03,.32]:
 tt=t-start;mask=(tt>=0)&(tt<.18);alarm+=mask*.13*np.sin(2*np.pi*790*tt)*np.maximum(0,np.sin(np.pi*np.clip(tt,0,.18)/.18))
write_wav('warning',alarm)
t=np.arange(int(.9*SR))/SR;write_wav('touchdown',(filt(rng.normal(0,1,len(t)),320)*.32+tone(55,t)*.13)*np.exp(-t*6)*envelope(t,.9))
# FFT noise is periodic, making these seamless cabin loops.
t=np.arange(int(16*SR))/SR;freq=np.fft.rfftfreq(len(t),1/SR)
noise=rng.normal(size=len(freq))+1j*rng.normal(size=len(freq));noise*=np.exp(-(freq/700)**2)*(freq/(freq+100));air=np.fft.irfft(noise,n=len(t));air/=max(abs(air))
write_wav('cabin_air',air*.19+tone(60,t)*.026+tone(120,t)*.013)
noise=rng.normal(size=len(freq))+1j*rng.normal(size=len(freq));noise*=np.exp(-(freq/220)**2);eng=np.fft.irfft(noise,n=len(t));eng/=max(abs(eng));write_wav('engine',eng*.24+tone(44,t)*.08+tone(88,t)*.03)
# Offline, bundled narration. This is a synthetic robot voice, not an impersonation.
ctypes.CDLL('libflite_usenglish.so.1',mode=ctypes.RTLD_GLOBAL);ctypes.CDLL('libflite_cmulex.so.1',mode=ctypes.RTLD_GLOBAL)
f=ctypes.CDLL('libflite.so.1',mode=ctypes.RTLD_GLOBAL);f.flite_init();v=ctypes.CDLL('libflite_cmu_us_slt.so.1',mode=ctypes.RTLD_GLOBAL)
v.register_cmu_us_slt.argtypes=[ctypes.c_char_p];v.register_cmu_us_slt.restype=ctypes.c_void_p;voice=v.register_cmu_us_slt(None)
f.flite_text_to_speech.argtypes=[ctypes.c_char_p,ctypes.c_void_p,ctypes.c_char_p];f.flite_text_to_speech.restype=ctypes.c_float
(OUT/'voice').mkdir(exist_ok=True);meta={}
for name,text in json.loads((ROOT/'mission/voice_lines.json').read_text()).items():
 with tempfile.NamedTemporaryFile(suffix='.wav') as tmp:
  f.flite_text_to_speech(text.encode(),voice,tmp.name.encode())
  with wave.open(tmp.name) as w:sr=w.getframerate();data=np.frombuffer(w.readframes(w.getnframes()),'<i2').astype(float)/32768
 data=filt(data,130,'highpass',sr);data=filt(data,5800,'lowpass',sr);data*=.78/max(.01,np.max(np.abs(data)))
 write_wav('voice/'+name,data,sr)
 block=sr//30;values=[float(np.sqrt(np.mean(data[i:i+block]**2))) for i in range(0,len(data),block)];mx=max(values)
 meta[name]={'duration':round(len(data)/sr,3),'envelope_fps':30,'envelope':[round(min(1,x/max(mx,.001)),3) for x in values]}
 print('voice',name,meta[name]['duration'],flush=True)
(OUT/'voice/envelopes.json').write_text(json.dumps(meta,separators=(',',':')))
credit=ROOT/'CREDITS_AUDIO.txt';credit.write_text('LUNA narration: offline synthetic speech generated with CMU Flite, SLT voice.\nNo real person is imitated. Runtime plays the included WAV files; no speech service is used.\n\nCabin ambience, engine sound, footfalls, UI tones, alerts, doors and ending cues:\noriginal procedural synthesis created for this game. No third-party sound samples.\n\nThe following distribution notices accompany the speech-generation toolchain;\nthe Flite executable/libraries are not bundled in the game.\n\n'+Path('/usr/share/doc/libflite1/copyright').read_text())
