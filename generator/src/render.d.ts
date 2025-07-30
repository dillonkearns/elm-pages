interface ElmModule {
  Elm: {
    Main: {
      init(arg0: { flags: MainFlags }): MainApp;
    };
    ScriptMain: {
      init(arg0: { flags: ScriptFlags }): ScriptApp;
    };
  };
}

// Ports

interface PortsFile {
  [x: string]: (arg0: unknown, arg1: Context) => unknown;
}

interface Ports {
  toJsPort: ToJsPort<FromElm>;
  fromJsPort: FromJsPort<{
    tag: string;
    data: ToElm;
  }>;

  gotBatchSub: FromJsPort<unknown>;
}

interface ToJsPort<T> {
  subscribe(arg0: (arg0: T) => Promise<void>): void;
  unsubscribe(arg0: (arg0: T) => Promise<void>): void;
}

interface FromJsPort<T> {
  send(arg0: T): void;
}

// Message from and to Elm
type FromElm =
  | { command: "log"; value: unknown }
  | { command: undefined; tag: "ApiResponse" }
  | ({ command: undefined } & PageProgress)
  | ({ command: undefined } & DoHttp);

type SeoTag = HeadTag | JsonLdTag;

interface HeadTag {
  type: "head";
  name: string;
  attributes: string[][];
}

interface JsonLdTag {
  type: "json-ld";
  contents: unknown;
}

interface PageProgress {
  tag: "PageProgress";
  args: [PageProgressArg];
}

interface PageProgressArg {
  headers: unknown;
  statusCode: unknown;
  route: string;
  is404: unknown;
  contentJson: unknown;
}

interface DoHttp {
  tag: "DoHttp";
  args: [DoHttpArg];
}

type DoHttpArg = [string, Pages_StaticHttp_Request | InternalRequest][];

interface Pages_StaticHttp_Request {
  url: string;
  method: string;
  headers: [string, string][];
  body: Pages_Internal_StaticHttpBody;
  cacheOptions: unknown | null;
  env: Env;
  dir: string[];
  quiet: boolean;
}

interface Env {
  [key: string]: string | undefined;
}

type Pages_Internal_StaticHttpBody =
  | Pages_Internal_EmptyBody
  | Pages_Internal_StringBody
  | Pages_Internal_JsonBody<unknown>
  | Pages_Internal_BytesBody;

interface Pages_Internal_EmptyBody {
  tag: "EmptyBody";
  args: [];
}
interface Pages_Internal_StringBody {
  tag: "StringBody";
  args: [string, string];
}

interface Pages_Internal_JsonBody<T> {
  tag: "JsonBody";
  args: [T];
}

interface Pages_Internal_BytesBody {
  tag: "BytesBody";
  args: [string, string];
}

interface ToElm {
  message: string;
  title: string;
}

/*****************************
 * Main app: rendering pages *
 *****************************/
interface MainFlags {
  mode: string;
  compatibilityKey: number;
  request: {
    payload: Payload;
    kind: string;
    jsonOnly: boolean;
  };
}

interface Payload {
  path: string;
  method: string;
  hostname: string;
  query: string;
  headers: unknown;
  host: string;
  pathname: string;
  port: string;
  protocol: string;
  rawUrl: string;
}

interface MainApp {
  ports: Ports;
}

interface ParsedRequest {
  method: string;
  hostname: string;
  query: Record<string, string | unknown>;
  headers: Record<string, string>;
  host: string;
  pathname: string;
  port: number | null;
  protocol: string;
  rawUrl: string;
}

/*******************************
 * Script app: running scripts *
 *******************************/

interface ScriptFlags {}

interface ScriptApp {
  ports: Ports;
  die(): void;
}

/*****************
 * Internal jobs *
 ****************/

interface Context {
  cwd: string;
  quiet: boolean;
  env: Env;
}

type InternalRequest =
  | LogRequest
  | ReadFileRequest
  | ReadFileBinaryRequest
  | GlobRequest
  | RandomSeedRequest
  | NowRequest
  | EnvRequest
  | EncryptRequest
  | DecryptRequest
  | WriteFileRequest
  | SleepRequest
  | WhichRequest
  | QuestionRequest
  | ShellRequest
  | StreamRequest
  | StartSpinnerRequest
  | StopSpinnerRequest;

type InternalResponse = [string, JsonResponse | BytesResponse] | ErrorResponse;

interface JsonResponse {
  request: InternalRequest;
  response: {
    bodyKind: "json";
    body: InnerJsonResponse;
  };
}

type InnerJsonResponse =
  | LogResponse
  | ReadFileResponse
  | GlobResponse
  | ErrorResponse
  | RandomSeedResponse
  | NowResponse
  | WhichResponse
  | StreamResponse;

interface BytesResponse {
  request: InternalRequest;
  response: {
    bodyKind: "bytes";
    body: string;
  };
}

interface ErrorResponse {
  errorCode: unknown;
}

// log
interface LogRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://log";
  body: Pages_Internal_JsonBody<{ message: string }>;
}

type LogResponse = null;

// read-file
interface ReadFileRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://read-file";
  body: Pages_Internal_StringBody;
}

interface ReadFileResponse {
  parsedFrontmatter: unknown;
  withoutFrontmatter: unknown;
  rawFile: string;
}

// read-file-binary
interface ReadFileBinaryRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://read-file-binary";
  body: Pages_Internal_StringBody;
}

// glob
interface GlobRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://glob";
  body: Pages_Internal_JsonBody<{ pattern: string; options: GlobOptions }>;
}

interface GlobOptions {
  dot: boolean;
  followSymbolicLinks: boolean;
  caseSensitiveMatch: boolean;
  gitignore: boolean;
  deep?: number;
  onlyFiles: boolean;
  onlyDirectories: boolean;
  stats: boolean;
}

type GlobResponse = (Glob | null)[];

interface Glob {
  fullPath: string;
  captures: string[] | null;
  fileStats: FileStats;
}

interface FileStats {
  size: number;
  atime: number;
  mtime: number;
  ctime: number;
  birthtime: number;
  fullPath: string;
  isDirectory: boolean;
}

// randomSeed
interface RandomSeedRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://randomSeed";
}

type RandomSeedResponse = number;

// now
interface NowRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://now";
}

type NowResponse = number;

// env
interface EnvRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://env";
  body: Pages_Internal_JsonBody<string>;
}

// encrypt
interface EncryptRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://encrypt";
  body: Pages_Internal_JsonBody<{ values: unknown; secret: string }>;
}

// decrypt
interface DecryptRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://decrypt";
  body: Pages_Internal_JsonBody<{ input: string; secrets: string[] }>;
}

// write-file
interface WriteFileRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://write-file";
  body: Pages_Internal_JsonBody<{ path: string; body: string }>;
}

// sleep
interface SleepRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://sleep";
  body: Pages_Internal_JsonBody<{ milliseconds: number }>;
}

// which
interface WhichRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://which";
  body: Pages_Internal_JsonBody<string>;
}

type WhichResponse = string;

// question
interface QuestionRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://question";
  body: Pages_Internal_JsonBody<{ prompt: string }>;
}

// shell
interface ShellRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://shell";
  body: Pages_Internal_JsonBody<ShellRequestBody>;
}

interface ShellRequestBody {
  captureOutput: boolean;
  commands: ElmCommand[];
}

interface ElmCommand {
  command: string;
  args: string[];
  timeout: number | null;
}

// stream
interface StreamRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://stream";
  body: Pages_Internal_JsonBody<StreamBody>;
}

type StreamBody = {
  kind: "none" | "text" | "json";
  parts: ({ [key: string]: unknown } & { name: string })[];
};

interface StreamResponse {
  body: unknown;
  metadata?: Metadata;
}

interface Metadata {
  headers: unknown;
  statusCode: unknown;
  url: unknown;
  statusText: unknown;
}

// start-spinner
interface StartSpinnerRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://start-spinner";
  body: Pages_Internal_JsonBody<StartSpinnerBody>;
}

interface StartSpinnerBody {
  text: string;
  spinnerId?: string;
  spinner?: string;
  immediateStart: boolean;
}

// stop-spinner
interface StopSpinnerRequest extends Pages_StaticHttp_Request {
  url: "elm-pages-internal://stop-spinner";
  body: Pages_Internal_JsonBody<StopSpinnerBody>;
}

interface StopSpinnerBody {
  spinnerId: string;
  completionFn: string;
  completionText: string | null;
}

/****************
 * Stream parts *
 ***************/

type StreamPart =
  | StreamPartWith<"unzip", {}>
  | StreamPartWith<"gzip", {}>
  | StreamPartWith<"stdin", {}>
  | StreamPartWith<"stdout", {}>
  | StreamPartWith<"stderr", {}>
  | StreamPartWith<"fromString", FromStringPartBody>
  | StreamPartWith<"command", CommandPartBody>
  | StreamPartWith<"httpWrite", HttpWritePartBody>
  | StreamPartWith<"fileRead", FileReadPartBody>
  | StreamPartWith<"fileWrite", FileWritePartBody>
  | StreamPartWith<"customRead", CustomReadPartBody>
  | StreamPartWith<"customWrite", CustomWritePartBody>
  | StreamPartWith<"customDuplex", CustomDuplexPartBody>;

type StreamPartWith<Key, Values> = { name: Key } & Values;

type FromStringPartBody = {
  string: string;
};

interface CommandPartBody {
  command: string;
  args: string[];
  allowNon0Status: boolean;
  output: "Ignore" | "Print" | "MergeWithStdout" | "InsteadOfStdout";
  timeoutInMs: number | null;
}

interface HttpWritePartBody {
  url: string;
  method: string;
  headers: {
    key: string;
    value: string;
  }[];
  body?: Pages_Internal_StaticHttpBody;
  retries: number | null;
  timeoutInMs: number | null;
}

interface FileReadPartBody {
  path: string;
}

interface FileWritePartBody {
  path: string;
}

interface CustomReadPartBody {
  portName: string;
  input: unknown;
}

interface CustomWritePartBody {
  portName: string;
  input: unknown;
}

interface CustomDuplexPartBody {
  portName: string;
  input: unknown;
}
