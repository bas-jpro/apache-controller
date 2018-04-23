/* Table Utilities */
/* JPRO 23/01/2006 */

/* Place rows of any tables in odd/even class */
function oddeven_rows() {
	if (!document.getElementsByTagName) {
		return;
	}

	var tbodys = document.getElementsByTagName("tbody");

	for (var t=0; t < tbodys.length; t++) {
		var rows = tbodys[t].getElementsByTagName("tr");

		for (var r=0; r < rows.length; r++) {
			if (r % 2) {
				rows[r].className = 'odd';
			} else {
				rows[r].className = 'even';
			}
		}
	}	
}

