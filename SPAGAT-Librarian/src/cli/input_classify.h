#ifndef INPUT_CLASSIFY_H
#define INPUT_CLASSIFY_H

typedef enum { INPUT_LLM, INPUT_SHELL } InputMode;

InputMode classify_input(const char *input);

#endif
