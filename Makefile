prove:
	prove rpl.t

critic:
	perlcritic --brutal ./rpl ./rpl.t

tidy:
	perltidy ./rpl ./rpl.t
