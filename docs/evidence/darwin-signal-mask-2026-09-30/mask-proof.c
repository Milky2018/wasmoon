#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static int phase, blocked_before, blocked_after;
static sigjmp_buf jump;
static void *worker(void *unused) {
  (void)unused;
  sigset_t mask;
  sigemptyset(&mask); sigaddset(&mask,SIGUSR2);
  pthread_sigmask(SIG_BLOCK,&mask,NULL);
  pthread_sigmask(SIG_SETMASK,NULL,&mask);
  blocked_before=sigismember(&mask,SIGUSR2);
  pthread_mutex_lock(&lock);
  phase=1; pthread_cond_signal(&condition);
  while(phase!=2)pthread_cond_wait(&condition,&lock);
  pthread_sigmask(SIG_SETMASK,NULL,&mask);
  blocked_after=sigismember(&mask,SIGUSR2);
  pthread_mutex_unlock(&lock);
  return NULL;
}
int main(int argc,char **argv) {
  int save=argc>1?atoi(argv[1]):1;
  pthread_t thread;
  pthread_create(&thread,NULL,worker,NULL);
  pthread_mutex_lock(&lock);
  while(phase!=1)pthread_cond_wait(&condition,&lock);
  if(sigsetjmp(jump,save)==0)siglongjmp(jump,1);
  phase=2; pthread_cond_signal(&condition);
  pthread_mutex_unlock(&lock);
  pthread_join(thread,NULL);
  printf("save_mask=%d worker_SIGUSR2_before=%d after=%d\n",save,blocked_before,blocked_after);
  return blocked_before!=blocked_after;
}
