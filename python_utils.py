import logging


def init_logging():
    # 2023-08-02 19:23:44 [0] "/home/whr/fs_gnn/dist_gcn_train.py", line 844, DEBUG: torch.Size([512, 500])
    # asctime: 时间戳，可指定格式
    # name: logger的名字
    # pathname: 调用日志输出函数的模块的完整路径名，可能没有
    # lineno: 调用日志输出函数的语句所在的代码行(所在文件内的行号)
    # levelname: 日志的最终等级(以字符串的形式显示)
    # message: 用户输出的消息(传入logger的参数)
    # reference: https://zhuanlan.zhihu.com/p/166671955

    # note: 如果是多进程，对logging模块的初始化需要在每个进程中都运行一次
    # 并且，logging模块是线程安全的，但并不是进程安全的
    # 如果要保证进程安全，需要将其它进程的消息汇总到一个进程，然后由同一进程中的某些logger（标识进程）来完成
    log_format = f'%(asctime)s %(name)s "%(pathname)s", line %(lineno)d, %(levelname)s: %(message)s\n'

    logging.basicConfig(
        level=logging.DEBUG,  # choices = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']
        format=log_format,
        datefmt="%Y-%m-%d %H:%M:%S",
        filename=f"log.log",
    )
