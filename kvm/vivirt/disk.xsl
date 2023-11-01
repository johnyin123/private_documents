<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="xml" indent="yes"/>

	<xsl:param name="file"/>
	<xsl:param name="unit">0</xsl:param>

	<!-- add  -->
	<xsl:template match="/domain/devices">
	  <xsl:copy>
		<xsl:apply-templates select="node()|@*"/>

		<disk type='file' device='disk'> 
			<driver name='qemu' type='qcow2'/> 
			<source file='{$file}'/> 
			<target dev='hda' bus='ide'/> 
			<address type='drive' controller='0' bus='1' target='0' unit='{$unit}'/>
		</disk> 
          </xsl:copy>
	</xsl:template>

	<!-- copy all other nodes and attributes -->
	<xsl:template match="node()|@*">
	  <xsl:copy>
	      <xsl:apply-templates select="node()|@*"/>
          </xsl:copy>
	</xsl:template>
</xsl:stylesheet>
