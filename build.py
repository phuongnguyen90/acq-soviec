# Chạy: python3 build.py  → đóng dấu phiên bản vào sw.js để mọi máy nhận bản mới
import time,re
v=time.strftime('%Y%m%d%H%M')
for f in ['sw.js']:
    t=open(f,encoding='utf-8').read(); t=re.sub(r"const VERSION = '[^']*'","const VERSION = '"+v+"'",t); open(f,'w',encoding='utf-8').write(t)
print('version',v)
