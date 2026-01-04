import sys
import bcrypt

userBytes = sys.argv[1].encode('utf-8')
hashBytes = sys.argv[2].encode('ascii')

print(sys.argv)
#hashBytes = '$2b$12$u32SPkm/ZfZRngbGNr66beqyXa1MOs1yrgfyhSPIVOaIHstklminq'.encode('utf-8')

result = bcrypt.checkpw(userBytes, hashBytes)
if result:
    print("OK match")
else:
    print("NG match")
