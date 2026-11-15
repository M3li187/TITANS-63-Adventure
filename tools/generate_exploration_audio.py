"""Original relaxing space score and boot foley; no downloaded audio samples.
Development only: Python/numpy/scipy and ffmpeg. Runtime uses bundled files.
"""
from pathlib import Path
import json, subprocess, tempfile, wave
import numpy as np
from scipy.signal import butter, sosfilt
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/audio'; SR=32000
rng=np.random.default_rng(6314)
def save(path,y,sr=SR):
    y=np.clip(y,-.98,.98)
    with wave.open(str(path),'wb') as w:
        w.setnchannels(1 if y.ndim==1 else y.shape[1]);w.setsampwidth(2);w.setframerate(sr)
        w.writeframes(np.round(y*32767).astype('<i2').tobytes())
def low(x,hz):return sosfilt(butter(3,hz,fs=SR,output='sos'),x)
# Each step combines heel/toe contact with a low boot/body-transmitted thud.
for surface in ['bridge','moon']:
 for i in range(3):
    d=.43 if surface=='bridge' else .48;t=np.arange(round(d*SR))/SR
    n=rng.normal(size=len(t));heel=np.exp(-t*(38 if surface=='bridge' else 25))
    toe_t=np.maximum(t-.085,0);toe=(t>=.085)*np.exp(-toe_t*35)
    if surface=='bridge':
        y=low(n,1500)*heel*.44 + low(np.roll(n,100),2100)*toe*.19
        for f,a,decay in [(92+i*3,.40,25),(181+i*5,.17,28),(370+i*7,.075,33)]:
            y+=np.sin(2*np.pi*f*t)*np.exp(-t*decay)*a
    else:
        # Filtered grit: contact is heard through the suit rather than lunar air.
        crunch=low(n,2800)-low(n,430)
        y=low(n,700)*heel*.43+crunch*(heel*.24+toe*.15)
        y+=np.sin(2*np.pi*(72+i*4)*t)*np.exp(-t*22)*.32
    y*=np.minimum(t/.005,1)*np.minimum((d-t)/.045,1)
    y*=.82/max(abs(y));save(OUT/f'footstep_{surface}_{i+1}.wav',y)
# A 96-second, eight-chord ambient composition. Add wrapped tails for a clean loop.
seconds=96;frames=seconds*SR;score=np.zeros((frames,2),dtype=np.float64)
def hz(midi):return 440*2**((midi-69)/12)
def add_wrapped(start,samples,pan=0):
    gains=np.sqrt(np.array([(1-pan)/2,(1+pan)/2]))
    data=samples[:,None]*gains[None,:]
    index=int(round(start*SR))%frames
    first=min(len(data),frames-index);score[index:index+first]+=data[:first]
    if first<len(data):score[:len(data)-first]+=data[first:]
chords=[[48,55,59,62,67],[45,52,55,59,64],[41,48,52,57,60],[43,50,55,57,62],
        [48,55,59,62,64],[40,47,52,55,62],[41,48,52,55,60],[43,50,55,57,62]]
for bar,notes in enumerate(chords):
    dur=18.;t=np.arange(int(dur*SR))/SR
    env=np.sin(np.minimum(t/5,1)*np.pi/2)**2*np.cos(np.maximum(t-11,0)/7*np.pi/2)**2
    for j,note in enumerate(notes):
        f=hz(note);phase=(bar*1.7+j*.83)
        sound=np.zeros_like(t)
        for detune,weight in [(-.018,.34),(0,.45),(.021,.34)]:
            angle=2*np.pi*f*(1+detune*.01)*t+phase
            sound+=weight*(np.sin(angle)+.15*np.sin(2*angle)+.035*np.sin(3*angle))
        sound*=env*.052*(.90+.1*np.sin(2*np.pi*t/13+phase))
        add_wrapped(bar*12-3,sound,pan=(j-2)*.28)
    # Sparse, soft arpeggio every three seconds, with two gentle stereo echoes.
    for beat in range(4):
        note=notes[[2,3,4,3][beat]]+12
        tt=np.arange(int(7.5*SR))/SR;f=hz(note)
        bell=(np.sin(2*np.pi*f*tt)+.17*np.sin(2*np.pi*f*2*tt))*np.exp(-tt/2.15)
        bell*=np.minimum(tt/.13,1)*np.minimum((7.5-tt)/.4,1)*.055
        when=bar*12+beat*3
        pan=.38 if (bar+beat)%2 else -.38
        add_wrapped(when,bell,pan)
        add_wrapped(when+.67,bell*.23,-pan)
        add_wrapped(when+1.34,bell*.10,pan)
# Tiny centering correction, then a gentle master level (mix volume is set in-game).
score-=score.mean(axis=0)
peak=float(abs(score).max());score*=.65/peak
music=OUT/'music';music.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as temp:
    wav=Path(temp)/'FraMauroStillness.wav';save(wav,score)
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','5',
                    '-metadata','title=Fra Mauro Stillness','-metadata','artist=TITANS original procedural score',
                    str(music/'fra_mauro_stillness.ogg')],check=True)
# Evidence for the original uncompressed cyclic master.
manifest={'title':'Fra Mauro Stillness','duration_seconds':seconds,'sample_rate':SR,'channels':2,
          'composition':'Original slow ambient pads and sparse soft arpeggios; no percussion; eight-chord cycle.',
          'master_peak':float(abs(score).max()),'master_rms':float(np.sqrt(np.mean(score**2))),
          'loop_boundary_delta':float(abs(score[0]-score[-1]).max()),
          'source':'Original deterministic synthesis; no third-party sound samples.'}
(music/'score_notes.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))

# Preserve the exploration-audio notice if the original narration helper was rerun.
credit=ROOT/'CREDITS_AUDIO.txt'
if credit.exists() and 'Exploration audio update' not in credit.read_text():
    credit.write_text(credit.read_text()+"\n\nExploration audio update"+'\n------------------------\nFra Mauro Stillness: original 96-second ambient score, synthesized for TITANS.\nWarm sustained chords and sparse soft arpeggios; no downloaded music or samples.\nBridge boot contacts and lunar suit-conducted boot/grit contacts: original\nprocedural foley, three variants per surface. No third-party sound samples.\nReproducible with tools/generate_exploration_audio.py; runtime uses the bundled\nWAV files and Ogg Vorbis music and requires no generator or online service.\n')
