import com.sun.net.httpserver.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

public final class ApkServer {
  private static final String APK="QuickPrintOS-v1.0.0-debug.apk";

  public static void main(String[] args) throws Exception {
    Path root=Path.of(args.length>0?args[0]:"/public");
    int port=Integer.parseInt(args.length>1?args[1]:"10000");
    HttpServer server=HttpServer.create(new InetSocketAddress("0.0.0.0",port),0);

    server.createContext("/",exchange->{
      if (!"GET".equalsIgnoreCase(exchange.getRequestMethod())) {
        send(exchange,405,"Método não permitido","text/plain; charset=utf-8");
        return;
      }

      if (("/"+APK).equals(exchange.getRequestURI().getPath())) {
        Path apk=root.resolve(APK);
        if (!Files.exists(apk)) {
          send(exchange,404,"APK não encontrado","text/plain; charset=utf-8");
          return;
        }
        Headers h=exchange.getResponseHeaders();
        h.set("Content-Type","application/vnd.android.package-archive");
        h.set("Content-Disposition","attachment; filename=\""+APK+"\"");
        h.set("Cache-Control","no-store");
        long size=Files.size(apk);
        exchange.sendResponseHeaders(200,size);
        try(OutputStream out=exchange.getResponseBody()){Files.copy(apk,out);}
        return;
      }

      String html="""
<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Quick Print OS</title>
<style>
body{font-family:system-ui,sans-serif;background:#f5f7fa;color:#142033;margin:0;padding:32px}
main{max-width:620px;margin:auto;background:white;border-radius:24px;padding:30px;box-shadow:0 12px 40px #14203318}
.bar{height:5px;background:linear-gradient(90deg,#159fe8 0 25%,#eb2f7d 25% 50%,#ffd21a 50% 75%,#111 75%);border-radius:8px;margin:22px 0}
a{display:inline-block;background:#159fe8;color:white;text-decoration:none;font-weight:700;padding:14px 20px;border-radius:14px}
small{color:#667085}
</style>
<main>
<h1>Quick Print OS</h1>
<p>v1.0.0 • APK interno de teste</p>
<div class="bar"></div>
<p>Build compilada para validação na gráfica.</p>
<p><a href="/QuickPrintOS-v1.0.0-debug.apk">Baixar APK</a></p>
<p><small>Pacote Android: br.com.quickprint.os</small></p>
</main>
</html>
""";
      send(exchange,200,html,"text/html; charset=utf-8");
    });

    server.start();
    System.out.println("APK server on port "+port);
  }

  private static void send(HttpExchange e,int status,String body,String type)throws IOException{
    byte[] bytes=body.getBytes(StandardCharsets.UTF_8);
    e.getResponseHeaders().set("Content-Type",type);
    e.sendResponseHeaders(status,bytes.length);
    try(OutputStream out=e.getResponseBody()){out.write(bytes);}
  }
}
