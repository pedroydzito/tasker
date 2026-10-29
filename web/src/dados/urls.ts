import { supabase } from "./nuvem";
import { lerArquivo } from "./espelho";

// Endereços de arquivos privados: uma leitura por arquivo para todas as peças que pedem
// (desempenho §4.21). O arquivo que está no aparelho vem primeiro (offline e sem rede);
// a URL assinada do bucket é guardada até perto de vencer, e uma falha limpa o guardado.

const guardadas = new Map<string, { promessa: Promise<string | null>; ate: number }>();
const locais = new Map<string, string>();

export function urlDoArquivo(bucket: string, caminho: string, baixarComo?: string): Promise<string | null> {
  const chave = `${bucket}/${caminho}${baixarComo ? "#" + baixarComo : ""}`;
  const g = guardadas.get(chave);
  if (g && g.ate > Date.now()) return g.promessa;
  const promessa = (async () => {
    const local = locais.get(`${bucket}/${caminho}`);
    if (local) return local;
    const blob = await lerArquivo(`${bucket}/${caminho}`).catch(() => undefined);
    if (blob) {
      // Uma URL de objeto por arquivo, com dono: vive enquanto o app vive (é a mesma para todos).
      const u = URL.createObjectURL(blob);
      locais.set(`${bucket}/${caminho}`, u);
      return u;
    }
    const { data, error } = await (await supabase()).storage.from(bucket).createSignedUrl(caminho, 3600, baixarComo ? { download: baixarComo } : undefined);
    if (error || !data) throw error ?? new Error("sem url");
    return data.signedUrl;
  })().catch(() => {
    guardadas.delete(chave);
    return null;
  });
  guardadas.set(chave, { promessa, ate: Date.now() + 50 * 60_000 });
  return promessa;
}

/** No logout, as URLs de objeto saem junto (são do aparelho, da conta que saiu). */
export function esquecerUrls() {
  for (const u of locais.values()) URL.revokeObjectURL(u);
  locais.clear();
  guardadas.clear();
}
