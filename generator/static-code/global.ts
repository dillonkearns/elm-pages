import type { ElmInstance, PortFromElm, PortToElm } from "elm";

type Flags = {
  secrets: Record<string, string> | null;
  isPrerendering: boolean;
  isDevServer: boolean;
  isElmDebugMode: boolean;
  contentJson: Record<string, unknown>;
  pageDataBase64: string;
  userFlags: unknown;
};

type Ports = {
  toJsPort: PortFromElm<unknown>;
  fromJsPort: PortToElm<unknown>;
};

declare global {
  export namespace globalThis {
    export const Elm: ElmInstance<Ports, Flags, ["Main"]>;
    export const connect: (
      sendContentJsonPort: any,
      initialErrorPage: any
    ) => void;
  }

  export interface Window {
    reloadOnOk: boolean;
    Elm: ElmInstance<Ports, Flags, ["Main"]>;
    connect: (sendContentJsonPort: any, initialErrorPage: any) => void;
  }
}
