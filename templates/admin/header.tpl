<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">

<!-- Apache::Controller::Interface Header Template -->
<!-- JPRO 23/01/2006                               -->

<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
	<head>
		<base href="http://$G_HOSTNAME/" />
		<link rel="stylesheet" type="text/css" href="/css/controller.css" />
		<script src="/js/table-utils.js" type="text/javascript"></script>
		<title>Apache::Controller::Interface</title>
	</head>

	<body onload="oddeven_rows()">
		<div id="title">Apache::Controller::Interface</div>

		<div id="menubar">
			<ul>
				<a href="$G_LOCATION/$G_LEVEL/"><li>List</li></a>
				<a href="$G_LOCATION/$G_LEVEL/add"><li>Add</li></a>
				<a href="$G_LOCATION/$G_LEVEL/sessions"><li>Sessions</li></a>
			</ul>
		</div>

		<div id="content">
			$CONTENT
		</div>

		$FOOTER
