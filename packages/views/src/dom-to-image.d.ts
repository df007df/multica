declare module "dom-to-image" {
  interface DomToImageOptions {
    width?: number;
    height?: number;
    style?: Record<string, string | number>;
    filter?: (node: HTMLElement) => boolean;
    bgcolor?: string;
    scale?: number;
    quality?: number;
    cacheBust?: boolean;
  }

  function toBlob(node: HTMLElement, options?: DomToImageOptions): Promise<Blob>;
  function toPixelData(node: HTMLElement, options?: DomToImageOptions): Promise<Uint8Array>;

  export default { toBlob, toPixelData };
}