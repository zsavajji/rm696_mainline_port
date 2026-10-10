#!/usr/bin/env python3
"""kprof-cats.py KPROF_OUTPUT: kprof's kernel symbols (KPROF_TOP=400) summed by subsystem."""
import re, sys
from collections import defaultdict

cats = [
    ('page copy/zero', r'^(copy_page|__memset|__memcpy|memset|memcpy|clear_user_highpage|copy_user_highpage|v6_copy|v6_clear|__memzero|clear_page)'),
    ('memcg', r'memcg|lruvec|uncharge|charge|rstat|css_|mem_cgroup|obj_cgroup'),
    ('fault-around/file map', r'next_uptodate_folio|filemap_map|file_rmap|filemap_fault|set_pte_range|finish_fault|do_fault'),
    ('page tables/cache/TLB', r'pte|pmd|pgd|pgtable|page_range|dcache_clean|icache|flush|tlb|v7wbi|cpu_v7|zap|vm_normal_page|walk|free_pgd_range|free_pgtables|cpu_switch_mm|switch_mm|asid'),
    ('fault entry', r'do_page_fault|handle_mm_fault|lock_mm_and_find_vma|do_wp_page|wp_page|do_translation_fault|do_DataAbort|do_PrefetchAbort|__dabt|__pabt|mm_account_fault|vma_.*fault|fault'),
    ('VMA/maple/anon_vma', r'^mas_|^mt_|^mtree|maple|vm_area|vma|anon_vma|interval_tree|mmap|unlink_|__remove_shared|vm_enough|mm_find|find_vma|dup_mmap|exit_mmap|unmap_vmas|uprobe|khugepaged|ksm'),
    ('slab', r'kmem_cache|slab|kfree|kmalloc|__kmalloc|krealloc|kvfree|pcpu|percpu'),
    ('page alloc/free', r'page_from_freelist|free_unref|frozen_pages|alloc_pages|free_pages|folios_put|folio_put|__folio_put|rmqueue|free_pcp|__free_one|buddy|split_page|post_alloc|prep_new|swap_cache|release_pages|__alloc_|free_pcppages|page_ref|folio_alloc'),
    ('LRU/rmap', r'lru|folio_add|rmap|folio_mark_accessed|folio_batch|__folio_batch|mapcount|folio_remove'),
    ('scheduler/switch', r'sched|switch|wake|enqueue|dequeue|pick|update_curr|update_load|vruntime|eevdf|place_entity|ttwu|try_to_wake|__schedule|schedule|resched|preempt|update_rq|cfs|entity|account_|cputime|dl_server|rq_|task_tick'),
    ('RCU/locks', r'rcu|_lock|_unlock|mutex|rwsem|down_|up_|spin|semaphore|percpu_down|percpu_up'),
    ('netlink/proc conn', r'netlink|cn_|connector|skb|sock|consume_skb|kfree_skb'),
    ('exit/fork/wait', r'do_exit|copy_process|release_task|wait|exit_|dup_fd|alloc_pid|free_pid|acct|randomness|dup_task|copy_|kernel_clone|ret_from_fork|put_task|free_task|delayed_put|__put_|cgroup|signal|sighand|pid|creds|cred|security|credp|validator|aegis|proc_|perf_event|fput|__fput|files|fs_struct|nsproxy|ns_'),
    ('syscall/irq entry', r'vector_swi|ret_fast|ret_to_user|__irq|gic|irq|do_work_pending|syscall|el0|__und|ret_from'),
]
tot = defaultdict(float)
top = defaultdict(list)
for l in open(sys.argv[1]):
    m = re.match(r'\s+([\d.]+)%\s+(\S+)$', l)
    if not m or 'symbols' in l:
        continue
    pct, sym = float(m.group(1)), m.group(2)
    for c, pat in cats:
        if re.search(pat, sym):
            break
    else:
        c = 'other'
    tot[c] += pct
    top[c].append((pct, sym))
for c, p in sorted(tot.items(), key=lambda x: -x[1]):
    print(f"{p:5.1f}%  {c:24s} " + ', '.join(f"{s} {v}" for v, s in sorted(top[c], reverse=True)[:6]))
print(f"{sum(tot.values()):5.1f}%  (symbols listed)")
