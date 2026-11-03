extends "res://addons/gut/hook_script.gd"

# GUT's normal exit code allows pending, empty, and assertion-free runs.
func run():
	var totals = gut.get_summary().get_totals()
	if totals.tests == 0 or totals.pending > 0 or totals.risky > 0 or totals.failing > 0:
		set_exit_code(1)
		push_error("Incomplete or unsuccessful GUT run: %s" % str(totals))
