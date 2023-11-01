<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="xml" indent="yes"/>

	<!-- the main template -->


	<!-- add  -->
	<xsl:template match="/domain/devices">
	  <xsl:copy>
	    <xsl:apply-templates select="node()|@*"/>
	    <serial type='pty'>
		<target port='0'/>
	    </serial>
	    <console type='pty'>
		<target type='serial' port='0'/>
	    </console>
          </xsl:copy>
	</xsl:template>

	<!-- copy all other nodes and attributes -->
	<xsl:template match="node()|@*">
	  <xsl:copy>
	      <xsl:apply-templates select="node()|@*"/>
          </xsl:copy>
	</xsl:template>
</xsl:stylesheet>
