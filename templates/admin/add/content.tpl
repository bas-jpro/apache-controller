<!-- Apache::Controller::Interface Add Template -->
<!-- v1.0 JPRO 24/01/2006                       -->


<form action="$G_LOCATION/$G_LEVEL/add" method="post">
	<input type="hidden" name="next_page_add" value="$G_LOCATION/$G_LEVEL/" />

	<div class="edit-row">
		<div><span class="$NAME_ERROR">Application Name</span></div>
		<input class="edit-row-input" type="string" name="name" value="$NAME" />
	</div>

	<div class="edit-row">
		<div><span class="$SITE_ERROR">Site</span></div>
		<input class="edit-row-input" type="string" name="site" value="$SITE" />
	</div>

	<div class="edit-row">
		<div><span class="$TITLE_ERROR">Title</span></div>
		<input class="edit-row-input" type="string" name="title" value="$TITLE" />
	</div>

	<div class="edit-row">
		<div><span class="$TEMPLATEDIR_ERROR">Template Directory</span></div>
		<input class="edit-row-input" type="string" name="templatedir" value="$TEMPLATEDIR" />
	</div>

	<div class="edit-row">
		<div><span class="$INTFILE_ERROR">Application File</span></div>
		<input class="edit-row-input" type="string" name="intfile" value="$INTFILE" />
	</div>

	<div class="edit-row">
		<div><span class="$GLOBALFILE_ERROR">Global File</span></div>
		<input class="edit-row-input" type="string" name="globalfile" value="$GLOBALFILE" />
	</div>

	<div class="edit-row">
		<div>&nbsp;</div>
		<input class="edit-row-submit" type="submit" name="CMD_add" value="Add Module" />
	</div>
</form>



