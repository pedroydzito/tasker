import { describe, expect, it } from "vitest";
import pacote from "../package.json";
import { NOVIDADES } from "./novidades";

describe("novidades", () => {
  it("a primeira versão da lista é a do package.json", () => {
    expect(NOVIDADES[0].versao).toBe(pacote.version);
  });
  it("cada versão respeita o teto (Z até 99, Y até 9) e tem nota", () => {
    for (const n of NOVIDADES) {
      const [, y, z] = n.versao.split(".").map(Number);
      expect(z).toBeLessThanOrEqual(99);
      expect(y).toBeLessThanOrEqual(9);
      expect(n.itens.length).toBeGreaterThan(0);
    }
  });
});
