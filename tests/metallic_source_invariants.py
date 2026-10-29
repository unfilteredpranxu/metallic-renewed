"""Read-only regression assertions against the device-tested application source."""
from pathlib import Path
import re,bisect,subprocess,collections,json
BASE='a3f24f56fb3169e031678c19184742977e7e3e55'
ROOT=Path(__file__).resolve().parent.parent
import os
os.chdir(ROOT)
def rawmethods(src):
 # Fix only the known baseline brace swallowed by an orientation comment, for boundary parsing.
 src=src.replace('return UIInterfaceOrientationMaskLandscape;   // landscape only }','return UIInterfaceOrientationMaskLandscape; }   // landscape only')
 classes=list(re.finditer(r'(?m)^@implementation (\w+)',src));starts=[m.start() for m in classes];out={}
 for m in re.finditer(r'(?m)^[-+] \(',src):
  i=src.find('{',m.start());semi=src.find(';',m.start())
  if i<0 or (semi>=0 and semi<i):continue
  clsindex=bisect.bisect_right(starts,m.start())-1
  if clsindex<0:continue
  cls=classes[clsindex][1];j=i;depth=0;state='code'
  while j<len(src):
   c=src[j];n=src[j+1] if j+1<len(src) else ''
   if state=='line':
    if c=='\n':state='code'
   elif state=='block':
    if c=='*' and n=='/':state='code';j+=1
   elif state in ['string','char']:
    if c=='\\':j+=1
    elif (state=='string' and c=='"') or (state=='char' and c=="'"):state='code'
   elif c=='/' and n=='/':state='line';j+=1
   elif c=='/' and n=='*':state='block';j+=1
   elif c=='"':state='string'
   elif c=="'":state='char'
   elif c=='{':depth+=1
   elif c=='}':
    depth-=1
    if depth==0:break
   j+=1
  assert depth==0,(cls,src[m.start():m.start()+90])
  signature=src[m.start():i].strip();key=cls+'|'+signature
  assert key not in out,key
  out[key]=src[m.start():j+1]
 return out
def old(name): return subprocess.check_output(['git','show',BASE+':ios-app/Natives/'+name],text=True)
def current(name): return Path('ios-app/Natives',name).read_text()
a,b=rawmethods(old('LauncherPreferencesViewController.m')),rawmethods(current('LauncherPreferencesViewController.m'))
k='LauncherPreferencesViewController|- (void)viewDidLoad'
assert a[k]==b[k], 'Original Settings factory/getters/setters modified'
active=re.sub(r'(?ms)^[ \t]*#if 0[ \t]*\n.*?^[ \t]*#endif[^\n]*','',b[k])
counts=collections.Counter(re.findall(r'@"type"\s*:\s*self\.(type\w+)',active))
assert dict(counts)=={'typeSwitch':43,'typePickField':16,'typeChildPane':5,'typeButton':14,'typeSlider':10,'typeTextField':2},counts
print('PASS original90 Settings descriptors and complete factory/read/write/default/availability body unchanged',dict(counts))
for name in ['DownloadViewController.m','DownloadTaskItem.m','DownloadTaskItem.h','JavaLauncher.m','LauncherRightPanelViewController.m','BackgroundManager.m','SurfaceViewController.m','PLPreferences.m','PLProfiles.m','ios_uikit_bridge.h','Info.plist','AppDelegate.m','SceneDelegate.m']:
 assert old(name)==current(name),name
print('PASS original Downloads providers/installers/search/profile snapshots; engine/JIT/Java/render/settings stores/identity/orientation byte-identical')
for name,parts in {'LauncherNewsViewController.m':['norightLaunchTapped','renewedReloadProfiles','showAccountManagerModal','fix2PushTab:','openCustomize'], 'BackgroundSettingsViewController.m':['SliderChanged:','resetInterfaceAppearance','documentPicker:']}.items():
 before=rawmethods(old(name));after=rawmethods(current(name))
 for part in parts:
  found=[k for k in before if part in k];assert found,part
  for k in found:assert before[k]==after[k],k
print('PASS canonical Home launch/account/profile/native forwarding and original Appearance mutations')
changed=subprocess.check_output(['git','diff',BASE,'--name-only','--','ios-app'],text=True).splitlines()
allowed={'AmeRootTabController.m','BackgroundSettingsViewController.m','HomeTopNavView.h','HomeTopNavView.m','LauncherNewsViewController.m','LauncherPreferencesViewController.m','PLPrefTableViewController.m','UpdateChecker.m','MinecraftResourceDownloadTask.m','DownloadTaskManager.m','DownloadTasksViewController.m','PLTaskProgressViewController.m','PLDownloadFileCommit.h','PLDownloadProgressMath.h'}
for path in changed:
 rel=path.removeprefix('ios-app/Natives/')
 assert rel in allowed or rel.startswith(('resources/MetallicUI/','resources/en.lproj/Localizable.strings','resources/Metallic-LICENSE.txt','Assets.xcassets/MetallicChromeTransparent.imageset/')),path
print('PASS changed application paths confined to reviewed UI/audio/localization and authorized download fixes')
s=current('LauncherNewsViewController.m');methods=rawmethods(s)
assert re.search(r'self\.displaySections\s*=\s*@\[\]', next(v for k,v in methods.items() if 'rebuildDisplaySections' in k))
for token in ['loadLatestNewsForTile','loadAnnouncementsForTile','checkMinecraftVersions']:
 body=next(v for k,v in methods.items() if k.endswith(')'+token));assert 'NSURLSession' not in body and 'dataTask' not in body
for key in ['home_tiles_config','ameHomeCardLayout']:
 assert key in s # Retired storage is retained, not migrated/deleted.
print('PASS legacy feed stays empty independently of persisted configuration; feed loaders inert')
subprocess.run(['git','diff','--check'],check=True)
