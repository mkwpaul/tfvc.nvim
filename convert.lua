require('ts-vimdoc').docgen({
	input_file='README.md',
	output_file = 'doc/tfvc.txt',
	project_name='tfvc',
})

vim.cmd.helptags "./doc/"

vim.print 'converted!'
