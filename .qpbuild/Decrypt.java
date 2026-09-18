import javax.crypto.Cipher;
import javax.crypto.spec.ChaCha20ParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Decrypt {
  public static void main(String[] args) throws Exception {
    if (args.length != 3) throw new IllegalArgumentException("usage: Decrypt <relayDir> <outDir> <keyB64>");
    Path relay=Path.of(args[0]), out=Path.of(args[1]);
    byte[] key=Base64.getDecoder().decode(args[2]);
    Files.createDirectories(out);

    for (int chunk=0; chunk<4; chunk++) {
      byte[] nonce=new byte[]{0x51,0x50,0x43,0x48,0x55,0x4e,0x4b,0x31,(byte)chunk,0,0,0};
      byte[] enc=Base64.getDecoder().decode(Files.readString(relay.resolve("chunk"+chunk+".b64")).trim());
      Cipher cipher=Cipher.getInstance("ChaCha20");
      cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key,"ChaCha20"),new ChaCha20ParameterSpec(nonce,1));
      byte[] plain=cipher.doFinal(enc);
      ByteBuffer b=ByteBuffer.wrap(plain).order(ByteOrder.BIG_ENDIAN);

      while (b.remaining() > 0) {
        int pathLen=b.getInt();
        byte[] pathBytes=new byte[pathLen]; b.get(pathBytes);
        int dataLen=b.getInt();
        byte[] data=new byte[dataLen]; b.get(data);
        String rel=new String(pathBytes,StandardCharsets.UTF_8);
        Path target=out.resolve(rel).normalize();
        if (!target.startsWith(out)) throw new SecurityException("invalid path");
        if (target.getParent()!=null) Files.createDirectories(target.getParent());
        Files.write(target,data);
      }
    }
  }
}
