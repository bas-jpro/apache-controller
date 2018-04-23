<!-- Apache::Controller::Interface Sessions List Template -->
<!-- JPRO 25/01/2006                                      -->

<form action="$G_LOCATION/$G_LEVEL/sessions" method="post">
	<input type="hidden" name="next_page_add_session" value="$G_LOCATION/$G_LEVEL/sessions" />
	<input type="hidden" name="next_page_del" value="$G_LOCATION/$G_LEVEL/sessions" />
	<input type="hidden" name="next_page_delold" value="$G_LOCATION/$G_LEVEL/sessions" />

	<div id="sessions">
		<ul>
			$SESSIONSS
		</ul>
	
		<input type="submit" name="CMD_add_session" value="Add Session" />
		<input type="submit" name="CMD_del" value="Delete Selected" />
		<input type="submit" name="CMD_delold" value="Delete Old Sessions" />
		Age (s) <input type="string" name="age" value="$AGE" />

	</div>
</form>


