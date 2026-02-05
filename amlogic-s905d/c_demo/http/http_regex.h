#ifndef __A_H_102030_1831859586__INC__
#define __A_H_102030_1831859586__INC__
#ifdef __cplusplus
extern "C" {
#endif

typedef void* regex;

struct regex_operator {
	int (*length)(regex rm);
	const char* (*get)(regex rm, int idx);
	void (*dump)(regex rm, int fd);
	int (*alloc)(const char* pattern, regex* prm);
	int (*free)(regex rm);
	int (*match)(const char* subject, int subject_len, regex rm);
	void (*reset)(regex rm);
};
extern struct regex_operator Regex;
#ifdef __cplusplus
}
#endif
#endif
