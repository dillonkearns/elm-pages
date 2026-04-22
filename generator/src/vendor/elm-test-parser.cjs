// @flow

// Vendored from elm-test (node_modules/elm-test/lib/Parser.js).
// Upstream: https://github.com/rtfeldman/node-test-runner
// License: BSD-3-Clause (copyright Richard Feldman and contributors).
//
// Exports `extractExposedPossiblyTests(filePath, createReadStream)` — a
// streaming Elm tokenizer that returns the list of exposed lowercase
// top-level names in a source file, without requiring valid Elm
// semantics. We vendor it so the `elm-pages test` discovery pipeline
// gets the same robustness as `elm-test` without taking an npm
// dependency on elm-test. Re-copy this file verbatim on elm-test
// upgrades.

// Useful for debugging.
const LOG_ERRORS = 'ELM_TEST_LOG_PARSE_ERRORS' in process.env;

// For valid Elm files, this extracts _all_ (no more, no less) names that:
// 1. Are exposed.
// 2. _Might_ be tests. So capitalized names are excluded, for example.
//
// For invalid Elm files, this probably returns an empty list. It could also
// return a list of things it _thinks_ are exposed values, but it doesn’t
// matter. The idea is to bail early and still import the file. Then Elm gets a
// chance to show its nice error messages.
//
// The only times the returned promise is rejected are:
//
// - When there’s a problem reading the file from disk.
// - If there’s a bug and an unexpected exception is thrown somewhere.
// - If `effect module` is encountered. That’s a real edge case. The gist of it
//   is that applications can’t contain effect modules and since the tests are
//   compiled as an application we can’t include effect modules.
//
// The tokenizer reads the file character by character. As soon as it’s produced
// a whole token it feeds it to the parser, which works token by token. Both
// parse just enough to be able to extract all exposed names that could be tests
// without false positives.
function extractExposedPossiblyTests(
  filePath /*: string */,
  createReadStream /*: (
    path: string,
    options?: { encoding?: string, ... }
  ) => stream$Readable & { close(): void } */
) /*: Promise<Array<string>> */ {
  return new Promise((resolve, reject) => {
    const exposedPossiblyTests /*: Array<string> */ = [];
    let tokenizerState /*: typeof TokenizerState */ = { tag: 'MaybeNewChunk' };
    let parserState /*: typeof ParserState */ = {
      tag: 'ModuleDeclaration',
      lastToken: 'Nothing',
    };
    let lastLowerName = '';
    let justSawCR = false;

    const readable = createReadStream(filePath, {
      encoding: 'utf8',
    });
    readable.on('error', reject);
    readable.on('data', onData);
    readable.on('close', () => {
      // There’s no need to flush here. It can’t result in more exposed names.
      resolve(exposedPossiblyTests);
    });

    function onData(chunk /*: string */) /*: void */ {
      for (let index = 0; index < chunk.length; index++) {
        const char = chunk[index];

        if (justSawCR) {
          if (char !== '\n') {
            // Elm only supports LF and CRLF, not CR by itself.
            Promise.resolve(expected('LF', char))
              .then(stop)
              .then(resolve, reject);
            readable.close();
            break;
          }
          justSawCR = false;
        } else if (char === '\r') {
          justSawCR = true;
          // Ignore CR so that the rest of the code can handle only LF.
          continue;
        }

        const result = tokenize(char, tokenizerState);
        if (!Array.isArray(result)) {
          Promise.resolve(result).then(stop).then(resolve, reject);
          readable.close();
          break;
        }

        const [nextTokenizerState, flushCommands] = result;
        let seenFlush = false;
        let hasFlushed = false;
        let flushResult = undefined;

        for (const flushCommand of flushCommands) {
          switch (flushCommand.tag) {
            case 'Flush':
              seenFlush = true;
              break;
            case 'FlushToken':
              if (flushResult === undefined) {
                hasFlushed = true;
                flushResult = flush(flushCommand.token);
              }
              break;
            default:
              unreachable(flushCommand.tag);
          }
        }

        if (seenFlush && !hasFlushed && flushResult === undefined) {
          flushResult = flush();
        }

        tokenizerState = nextTokenizerState;

        if (flushResult !== undefined) {
          Promise.resolve(flushResult).then(stop).then(resolve, reject);
          readable.close();
          break;
        }
      }
    }

    function flush(
      token /*: typeof Token | void */
    ) /*: typeof OnParserTokenResult | void */ {
      if (
        tokenizerState.tag === 'Initial' &&
        tokenizerState.otherTokenChars !== ''
      ) {
        const value = tokenizerState.otherTokenChars;
        tokenizerState.otherTokenChars = '';
        const error = onParserToken(
          isLowerName(value)
            ? { tag: 'LowerName', value }
            : isUpperName(value)
            ? { tag: 'UpperName', value }
            : { tag: 'Other', value }
        );
        if (error !== undefined) {
          return error;
        }
      }
      if (token !== undefined) {
        return onParserToken(token);
      }
      return undefined;
    }

    function stop(
      result /*: typeof OnParserTokenResult */
    ) /*: Array<string> */ {
      switch (result.tag) {
        case 'ParseError':
          if (LOG_ERRORS) {
            console.error(`${filePath}: ${result.message}`);
          }
          return [];

        case 'CriticalParseError':
          throw new Error(
            `This file is problematic:\n\n${filePath}\n\n${result.message}`
          );

        case 'StopParsing':
          return exposedPossiblyTests;

        default:
          return unreachable(result);
      }
    }

    function onParserToken(
      token /*: typeof Token */
    ) /*: typeof OnParserTokenResult | void */ {
      if (token.tag === 'LowerName') {
        lastLowerName = token.value;
      }
      switch (parserState.tag) {
        case 'ModuleDeclaration': {
          const rawResult = parseModuleDeclaration(
            token,
            parserState.lastToken
          );
          const result =
            typeof rawResult === 'string'
              ? { tag: 'Token', token: rawResult }
              : rawResult;
          switch (result.tag) {
            case 'ParseError':
            case 'CriticalParseError':
            case 'StopParsing':
              return result;
            case 'NextParserState':
              parserState = { tag: 'Rest', lastToken: 'Initial' };
              break;
            case 'Token':
              parserState.lastToken = result.token;
              if (result.token === 'LowerName') {
                exposedPossiblyTests.push(lastLowerName);
              }
              break;
            default:
              unreachable(result);
          }
          break;
        }

        case 'Rest': {
          const rawResult = parseRest(token, parserState.lastToken);
          const result =
            typeof rawResult === 'string'
              ? { tag: 'Token', token: rawResult }
              : rawResult;
          switch (result.tag) {
            case 'ParseError':
              return result;
            case 'Token':
              parserState.lastToken = result.token;
              if (result.token === 'PotentialTestDeclaration=') {
                exposedPossiblyTests.push(lastLowerName);
              }
              break;
            default:
              unreachable(result);
          }
          break;
        }

        default:
          unreachable(parserState.tag);
      }
    }
  });
}

// First char lowercase: https://github.com/elm/compiler/blob/2860c2e5306cb7093ba28ac7624e8f9eb8cbc867/compiler/src/Parse/Variable.hs#L296-L300
// First char uppercase: https://github.com/elm/compiler/blob/2860c2e5306cb7093ba28ac7624e8f9eb8cbc867/compiler/src/Parse/Variable.hs#L263-L267
// Rest: https://github.com/elm/compiler/blob/2860c2e5306cb7093ba28ac7624e8f9eb8cbc867/compiler/src/Parse/Variable.hs#L328-L335
// https://hackage.haskell.org/package/base-4.14.0.0/docs/Data-Char.html#v:isLetter
const lowerName = /^\p{Ll}[_\d\p{L}]*$/u;
const upperName = /^\p{Lu}[_\d\p{L}]*$/u;
const anyNameFirstChar = /^\p{L}$/u;

// https://github.com/elm/compiler/blob/2860c2e5306cb7093ba28ac7624e8f9eb8cbc867/compiler/src/Parse/Variable.hs#L71-L81
const reservedWords = new Set([
  'if',
  'then',
  'else',
  'case',
  'of',
  'let',
  'in',
  'type',
  'module',
  'where',
  'import',
  'exposing',
  'as',
  'port',
]);

const validNewChunkKeywordsAfterModuleDeclaration = new Set([
  'import',
  'port',
  'type',
]);

// https://github.com/elm/compiler/blob/2860c2e5306cb7093ba28ac7624e8f9eb8cbc867/compiler/src/Parse/String.hs#L279-L285
const backslashableChars = new Set([
  'n',
  'r',
  't',
  '"',
  "'",
  '\\',
  // Note: `u` must be followed by for example `{1234}`.
  // In strings and multiline strings, we can just pretend that `\u` is the
  // escape and `{1234}` is just regular text, for simplicity.
  // In char literals, we need some extra handling.
  'u',
]);

function isLowerName(string) {
  return lowerName.test(string) && !reservedWords.has(string);
}

function isUpperName(string /*: string */) /*: boolean */ {
  return upperName.test(string);
}

function unreachable(value /*: empty */) /*: empty */ {
  throw new Error(`Unreachable: ${value}`);
}

// Poor man’s type alias. We can’t use /*:: type ParseError = ... */ because of:
// https://github.com/prettier/prettier/issues/2597
// There are a couple of more of this workaround throughout the file.
const ParseError /*: {
  tag: 'ParseError',
  message: string,
  -[mixed]: empty, // https://github.com/facebook/flow/issues/7859
} */ = {
  tag: 'ParseError',
  message: '',
};
void ParseError;

const CriticalParseError /*: {
  tag: 'CriticalParseError',
  message: string,
} */ = {
  tag: 'CriticalParseError',
  message: '',
};
void CriticalParseError;

const OnParserTokenResult /*:
  | typeof ParseError
  | typeof CriticalParseError
  | { tag: 'StopParsing' } */ = ParseError;
void OnParserTokenResult;

function expected(
  expectedDescription /*: string */,
  actual /*: mixed */
) /*: typeof ParseError */ {
  return {
    tag: 'ParseError',
    message: `Expected ${expectedDescription} but got: ${stringify(actual)}`,
  };
}

function stringify(json /*: mixed */) /*: string */ {
  const maybeString = JSON.stringify(json);
  return maybeString === undefined ? 'undefined' : maybeString;
}

function backslashError(actual) {
  return expected(
    `one of \`${Array.from(backslashableChars).join(' ')}\``,
    actual
  );
}

const Token /*:
  | { tag: '(' }
  | { tag: ')' }
  | { tag: ',' }
  | { tag: '=' }
  | { tag: '.' }
  | { tag: '..' }
  | { tag: 'Char' }
  | { tag: 'String' }
  | { tag: 'NewChunk' }
  | { tag: 'LowerName', value: string }
  | { tag: 'UpperName', value: string }
  | { tag: 'Other', value: string } */ = { tag: '(' };
void Token;

const TokenizerState /*:
  | { tag: 'Initial', otherTokenChars: string }
  | { tag: 'MaybeNewChunk' }
  | { tag: 'MaybeMultilineComment{' }
  | { tag: 'MultilineComment', level: number }
  | { tag: 'MultilineComment{', level: number }
  | { tag: 'MultilineComment-', level: number }
  | { tag: 'MaybeSinglelineComment-' }
  | { tag: 'SinglelineComment' }
  | { tag: 'Maybe..' }
  | { tag: 'CharStart' }
  | { tag: 'CharBackslash' }
  | { tag: 'CharUnicodeEscape' }
  | { tag: 'CharEnd' }
  | { tag: 'StringStart' }
  | { tag: 'StringContent' }
  | { tag: 'StringBackslash' }
  | { tag: 'EmptyStringMaybeTriple' }
  | { tag: 'MultilineString' }
  | { tag: 'MultilineStringBackslash' }
  | { tag: 'MultilineString"' }
  | { tag: 'MultilineString""' } */ = {
  tag: 'Initial',
  otherTokenChars: '',
};
void TokenizerState;

function tokenize(
  char /*: string */,
  tokenizerState /*: typeof TokenizerState */
) /*:
  | [
      typeof TokenizerState,
      Array<{ tag: 'Flush' } | { tag: 'FlushToken', token: typeof Token }>
    ]
  | typeof ParseError */ {
  switch (tokenizerState.tag) {
    case 'Initial':
      switch (char) {
        case ' ':
          return [tokenizerState, [{ tag: 'Flush' }]];
        case '\n':
          return [{ tag: 'MaybeNewChunk' }, [{ tag: 'Flush' }]];
        case '{':
          return [{ tag: 'MaybeMultilineComment{' }, [{ tag: 'Flush' }]];
        case '-':
          return [{ tag: 'MaybeSinglelineComment-' }, [{ tag: 'Flush' }]];
        case '.':
          return [{ tag: 'Maybe..' }, [{ tag: 'Flush' }]];
        case '(':
          return [tokenizerState, [{ tag: 'FlushToken', token: { tag: '(' } }]];
        case ')':
          return [tokenizerState, [{ tag: 'FlushToken', token: { tag: ')' } }]];
        case ',':
          return [tokenizerState, [{ tag: 'FlushToken', token: { tag: ',' } }]];
        case '=':
          return [tokenizerState, [{ tag: 'FlushToken', token: { tag: '=' } }]];
        case "'":
          return [{ tag: 'CharStart' }, [{ tag: 'Flush' }]];
        case '"':
          return [{ tag: 'StringStart' }, [{ tag: 'Flush' }]];
        default:
          return [
            {
              tag: 'Initial',
              otherTokenChars: tokenizerState.otherTokenChars + char,
            },
            [],
          ];
      }

    case 'MaybeNewChunk':
      switch (char) {
        case ' ':
          return [{ tag: 'Initial', otherTokenChars: '' }, []];
        case '\n':
          return [{ tag: 'MaybeNewChunk' }, []];
        case '{':
          return [{ tag: 'MaybeMultilineComment{' }, [{ tag: 'Flush' }]];
        case '-':
          return [{ tag: 'MaybeSinglelineComment-' }, [{ tag: 'Flush' }]];
        default:
          if (anyNameFirstChar.test(char)) {
            return [
              {
                tag: 'Initial',
                otherTokenChars: char,
              },
              [{ tag: 'FlushToken', token: { tag: 'NewChunk' } }],
            ];
          } else {
            return expected('a letter', char);
          }
      }

    case 'MaybeMultilineComment{':
      switch (char) {
        case '-':
          return [{ tag: 'MultilineComment', level: 1 }, []];
        default:
          return tokenizeInitial('{', char, []);
      }

    case 'MultilineComment':
      switch (char) {
        case '{':
          return [
            { tag: 'MultilineComment{', level: tokenizerState.level },
            [],
          ];
        case '-':
          return [
            { tag: 'MultilineComment-', level: tokenizerState.level },
            [],
          ];
        default:
          return [tokenizerState, []];
      }

    case 'MultilineComment{':
      switch (char) {
        case '-':
          return [
            { tag: 'MultilineComment', level: tokenizerState.level + 1 },
            [],
          ];
        case '{':
          return [
            { tag: 'MultilineComment{', level: tokenizerState.level },
            [],
          ];
        default:
          return [{ tag: 'MultilineComment', level: tokenizerState.level }, []];
      }

    case 'MultilineComment-':
      switch (char) {
        case '}':
          return [
            tokenizerState.level <= 1
              ? { tag: 'Initial', otherTokenChars: '' }
              : { tag: 'MultilineComment', level: tokenizerState.level - 1 },
            [],
          ];
        case '{':
          return [
            { tag: 'MultilineComment{', level: tokenizerState.level },
            [],
          ];
        case '-':
          return [
            { tag: 'MultilineComment-', level: tokenizerState.level },
            [],
          ];
        default:
          return [{ tag: 'MultilineComment', level: tokenizerState.level }, []];
      }

    case 'MaybeSinglelineComment-':
      switch (char) {
        case '-':
          return [{ tag: 'SinglelineComment' }, []];
        default:
          return tokenizeInitial('-', char, []);
      }

    case 'SinglelineComment':
      switch (char) {
        case '\n':
          return [{ tag: 'Initial', otherTokenChars: '' }, []];
        default:
          return [tokenizerState, []];
      }

    case 'Maybe..':
      switch (char) {
        case '.':
          return [
            { tag: 'Initial', otherTokenChars: '' },
            [{ tag: 'FlushToken', token: { tag: '..' } }],
          ];
        default:
          return tokenizeInitial('', char, [
            { tag: 'FlushToken', token: { tag: '.' } },
          ]);
      }

    case 'CharStart':
      switch (char) {
        case '\n':
          return expected('a non-newline', char);
        case '\\':
          return [{ tag: 'CharBackslash' }, []];
        default:
          return [{ tag: 'CharEnd' }, []];
      }

    case 'CharBackslash':
      if (char === 'u') {
        return [{ tag: 'CharUnicodeEscape' }, []];
      } else if (backslashableChars.has(char)) {
        return [{ tag: 'CharEnd' }, []];
      } else {
        return backslashError(char);
      }

    case 'CharUnicodeEscape':
      switch (char) {
        case "'":
          return [
            { tag: 'Initial', otherTokenChars: '' },
            [{ tag: 'FlushToken', token: { tag: 'Char' } }],
          ];
        // Note: This allows invalid escapes like `\u}abc{1` or `\u{FFFFFFFFFF}`.
        // It’s not worth parsing this exactly – see the comment at the top of this file.
        case '{':
        case '}':
        case 'a':
        case 'A':
        case 'b':
        case 'B':
        case 'c':
        case 'C':
        case 'd':
        case 'D':
        case 'e':
        case 'E':
        case 'f':
        case 'F':
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
          return [{ tag: 'CharUnicodeEscape' }, []];
        default:
          return expected("a valid unicode escape or `'`", char);
      }

    case 'CharEnd':
      switch (char) {
        case "'":
          return [
            { tag: 'Initial', otherTokenChars: '' },
            [{ tag: 'FlushToken', token: { tag: 'Char' } }],
          ];
        default:
          return expected("`'`", char);
      }

    case 'StringStart':
      switch (char) {
        case '\n':
          return expected('a non-newline', char);
        case '\\':
          return [{ tag: 'StringBackslash' }, []];
        case '"':
          return [{ tag: 'EmptyStringMaybeTriple' }, []];
        default:
          return [{ tag: 'StringContent' }, []];
      }

    case 'StringContent':
      switch (char) {
        case '\n':
          return expected('a non-newline', char);
        case '\\':
          return [{ tag: 'StringBackslash' }, []];
        case '"':
          return [
            { tag: 'Initial', otherTokenChars: '' },
            [{ tag: 'FlushToken', token: { tag: 'String' } }],
          ];
        default:
          return [{ tag: 'StringContent' }, []];
      }

    case 'StringBackslash':
      if (backslashableChars.has(char)) {
        return [{ tag: 'StringContent' }, []];
      } else {
        return backslashError(char);
      }

    case 'EmptyStringMaybeTriple':
      switch (char) {
        case '"':
          return [{ tag: 'MultilineString' }, []];
        default:
          return tokenizeInitial('', char, [
            { tag: 'FlushToken', token: { tag: 'String' } },
          ]);
      }

    case 'MultilineString':
      switch (char) {
        case '"':
          return [{ tag: 'MultilineString"' }, []];
        case '\\':
          return [{ tag: 'MultilineStringBackslash' }, []];
        default:
          return [{ tag: 'MultilineString' }, []];
      }

    case 'MultilineString"':
      switch (char) {
        case '"':
          return [{ tag: 'MultilineString""' }, []];
        case '\\':
          return [{ tag: 'MultilineStringBackslash' }, []];
        default:
          return [{ tag: 'MultilineString' }, []];
      }

    case 'MultilineString""':
      switch (char) {
        case '"':
          return [
            { tag: 'Initial', otherTokenChars: '' },
            [{ tag: 'FlushToken', token: { tag: 'String' } }],
          ];
        case '\\':
          return [{ tag: 'MultilineStringBackslash' }, []];
        default:
          return [{ tag: 'MultilineString' }, []];
      }

    case 'MultilineStringBackslash':
      if (backslashableChars.has(char)) {
        return [{ tag: 'MultilineString' }, []];
      } else {
        return backslashError(char);
      }

    default:
      return unreachable(tokenizerState.tag);
  }
}

function tokenizeInitial(previousChar, char, cmds) {
  const result = tokenize(char, {
    tag: 'Initial',
    otherTokenChars: previousChar,
  });
  if (result.tag === 'ParseError') {
    return result;
  }
  const [nextTokenizerState, nextCmds] = result;
  return [nextTokenizerState, cmds.concat(nextCmds)];
}

const ParserState /*:
  | {
      tag: 'ModuleDeclaration',
      lastToken: typeof ModuleDeclarationLastToken,
    }
  | {
      tag: 'Rest',
      lastToken: typeof RestLastToken,
    } */ = { tag: 'ModuleDeclaration', lastToken: 'Nothing' };
void ParserState;

const ModuleDeclarationLastToken /*:
  | 'Nothing'
  | 'NewChunk'
  | 'port'
  | 'module'
  | 'ModuleName'
  | 'ModuleName.'
  | 'exposing'
  | 'exposing('
  | 'exposing..'
  | 'LowerName'
  | 'UpperName'
  | 'UpperName('
  | 'UpperName..'
  | 'UpperName)'
  | ',' */ = 'Nothing';
void ModuleDeclarationLastToken;

function parseModuleDeclaration(
  token /*: typeof Token */,
  lastToken /*: typeof ModuleDeclarationLastToken */
) /*:
  | typeof ModuleDeclarationLastToken
  | { tag: 'NextParserState' }
  | typeof OnParserTokenResult */ {
  switch (lastToken) {
    case 'Nothing':
      if (token.tag === 'NewChunk') {
        return 'NewChunk';
      }
      return expected('a new chunk', token);

    case 'NewChunk':
      switch (token.tag) {
        case 'LowerName':
        case 'Other':
          switch (token.value) {
            case 'port':
              return 'port';
            case 'effect': // Not a reserved word, so this is a LowerName.
              return {
                tag: 'CriticalParseError',
                message:
                  'It starts with `effect module`. Effect modules can only exist inside src/ in elm and elm-explorations packages. They cannot contain tests.',
              };
            case 'module':
              return 'module';
          }
      }
      return expected('`port` or `module`', token);

    case 'port':
      if (token.tag === 'Other' && token.value === 'module') {
        return 'module';
      }
      return expected('`module`', token);

    case 'module':
      if (token.tag === 'UpperName') {
        return 'ModuleName';
      }
      return expected('a module name', token);

    case 'ModuleName':
      switch (token.tag) {
        case '.':
          return 'ModuleName.';
        case 'Other':
          if (token.value === 'exposing') {
            return 'exposing';
          }
      }
      return expected('`.` or `exposing`', token);

    case 'ModuleName.':
      if (token.tag === 'UpperName') {
        return 'ModuleName';
      }
      return expected('a module name', token);

    case 'exposing':
      if (token.tag === '(') {
        return 'exposing(';
      }
      return expected('`(`', token);

    case 'exposing(':
      switch (token.tag) {
        case '..':
          return 'exposing..';
        case 'LowerName':
          return 'LowerName';
        case 'UpperName':
          return 'UpperName';
      }
      return expected('an exposed name or `..`', token);

    case 'exposing..':
      if (token.tag === ')') {
        return { tag: 'NextParserState' };
      }
      return expected('`)`', token);

    case 'LowerName':
      switch (token.tag) {
        case ',':
          return ',';
        case ')':
          return { tag: 'StopParsing' };
      }
      return expected('`)` or `,`', token);

    case 'UpperName':
      switch (token.tag) {
        case ',':
          return ',';
        case '(':
          return 'UpperName(';
        case ')':
          return { tag: 'StopParsing' };
      }
      return expected('`(`, `)` or `,`', token);

    case 'UpperName(':
      if (token.tag === '..') {
        return 'UpperName..';
      }
      return expected('`..`', token);

    case 'UpperName..':
      if (token.tag === ')') {
        return 'UpperName)';
      }
      return expected('`)`', token);

    case 'UpperName)':
      switch (token.tag) {
        case ',':
          return ',';
        case ')':
          return { tag: 'StopParsing' };
      }
      return expected('`)` or `,`', token);

    case ',':
      switch (token.tag) {
        case 'LowerName':
          return 'LowerName';
        case 'UpperName':
          return 'UpperName';
      }
      return expected('an exposed name', token);

    default:
      return unreachable(lastToken);
  }
}

const RestLastToken /*:
  | 'Initial'
  | 'NewChunk'
  | 'PotentialTestDeclarationName'
  | 'PotentialTestDeclaration='
  | 'Ignore' */ = 'Initial';
void RestLastToken;

function parseRest(
  token /*: typeof Token */,
  lastToken /*: typeof RestLastToken */
) /*: typeof RestLastToken | typeof ParseError */ {
  switch (lastToken) {
    case 'Initial':
      if (token.tag === 'NewChunk') {
        return 'NewChunk';
      }
      return expected('a new chunk', token);

    case 'NewChunk':
      switch (token.tag) {
        case 'LowerName':
          return 'PotentialTestDeclarationName';
        case 'Other':
          if (validNewChunkKeywordsAfterModuleDeclaration.has(token.value)) {
            return 'Ignore';
          }
          break;
      }
      return expected(
        `${Array.from(
          validNewChunkKeywordsAfterModuleDeclaration,
          (keyword) => `\`${keyword}\``
        ).join(', ')} or a name`,
        token
      );

    case 'PotentialTestDeclarationName':
      if (token.tag === '=') {
        return 'PotentialTestDeclaration=';
      }
      return 'Ignore';

    case 'PotentialTestDeclaration=':
      if (token.tag === 'NewChunk') {
        return expected('a definition', token);
      }
      return 'Ignore';

    case 'Ignore':
      if (token.tag === 'NewChunk') {
        return 'NewChunk';
      }
      return 'Ignore';

    default:
      return unreachable(lastToken);
  }
}

module.exports = {
  extractExposedPossiblyTests,
  isUpperName,
};
