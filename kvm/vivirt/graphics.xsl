<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="xml" indent="yes"/>

	<!-- the main template -->


	<!-- replace  -->
	<xsl:template match="/domain/devices/graphics">
		<graphics type='vnc' port='-1' autoport='yes'/>
	</xsl:template>

	<!-- copy all other nodes and attributes -->
	<xsl:template match="node()|@*">
	  <xsl:copy>
	      <xsl:apply-templates select="node()|@*"/>
          </xsl:copy>
	</xsl:template>
</xsl:stylesheet>
